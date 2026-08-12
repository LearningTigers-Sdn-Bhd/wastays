# frozen_string_literal: true

module Onboarding
  # The offers that reduce what a guest owes.
  #
  # Like extra charges, the page arrives prefilled with the seeded adjustment
  # code as an unsaved row, so Discounts::EnsureDefaults is not called here —
  # running it per save would resurrect a row the owner had just removed.
  class SaveDiscounts
    include CommercialRows

    Result = ApplicationResult.define(:section, :entries)

    ENTRY_FIELDS = %w[
      id transaction_code_id client_key _destroy
      name code description pricing_type rate_value application_scope
      allow_amount_override active applicable_transaction_code_ids
    ].freeze

    RECORD_LABEL = "Discount"
    FAILURE_MESSAGE = "Discounts could not be saved."

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, entries:, complete:)
      @hotel = hotel
      @actor = actor
      @entries = entries
      @complete = complete
    end

    def call
      return failure(foreign_reference_error) if foreign_reference_error.present?
      return failure(duplicate_code_error) if duplicate_code_error.present?
      return failure("Add at least one discount, or choose no discounts for now.") if complete && retained_rows.empty?

      transition = nil

      Hotel.transaction do
        destroy_rows!
        save_rows!

        transition = transition_section
        fail_transaction!(transition.error) unless transition.success?
      end

      return failure(@error) if @error.present?

      Result.success(section: transition.section, entries: persisted_entries)
    rescue ActiveRecord::RecordNotFound
      failure("One or more submitted discounts do not belong to this property.")
    end

    private

    attr_reader :hotel, :actor, :complete

    def destroy_rows!
      discarded_rows.each { |row| existing_discounts.fetch(row["id"].to_s).destroy! }
    end

    def save_rows!
      retained_rows.each_with_index do |row, index|
        discount = build_or_find_discount(row)
        discount.position = index

        # Discounts::Save writes its join rows before checking validity and
        # unwinds with a bare ActiveRecord::Rollback of its own. Nested here that
        # Rollback only exits its own block, so the outer transaction is what
        # actually undoes those writes — which means the result has to be checked
        # and re-raised rather than trusted to have cleaned up after itself.
        result = Discounts::Save.call(discount: discount, attributes: row)
        next if result.success?

        fail_transaction!(row_error(index, result.error))
      end
    end

    def build_or_find_discount(row)
      return existing_discounts.fetch(row["id"].to_s) if row["id"].present?
      return HotelDiscount.new(hotel: hotel, transaction_code: adoptable_codes.fetch(row["transaction_code_id"].to_s)) if row["transaction_code_id"].present?

      HotelDiscount.new(
        hotel: hotel,
        transaction_code: TransactionCode.new(
          hotel: hotel, kind: "adjustment", category: "discount", active: true, system_required: false
        )
      )
    end

    def foreign_reference_error
      return @foreign_reference_error if defined?(@foreign_reference_error)

      submitted_ids = rows.filter_map { |row| row["id"].presence&.to_s }
      submitted_codes = retained_rows.filter_map { |row| row["transaction_code_id"].presence&.to_s }

      @foreign_reference_error =
        if submitted_ids.any? { |id| !existing_discounts.key?(id) } ||
           submitted_codes.any? { |id| !adoptable_codes.key?(id) }
          "One or more submitted discounts do not belong to this property."
        end
    end

    def transition_section
      UpdateSection.new(
        hotel: hotel,
        section_key: "discounts",
        state: complete ? "complete" : "in_progress",
        actor: actor,
        metadata: { source: "discount_setup", discount_count: hotel.hotel_discounts.reload.size }
      ).call
    end

    def existing_discounts
      @existing_discounts ||= hotel.hotel_discounts.includes(:transaction_code).index_by { |discount| discount.id.to_s }
    end

    # The seeded rebate code, while nothing has claimed it — one discount per
    # code, same as extra charges.
    def adoptable_codes
      @adoptable_codes ||= hotel.transaction_codes
                                .where(kind: "adjustment", category: "discount")
                                .where.missing(:hotel_discount)
                                .index_by { |code| code.id.to_s }
    end

    def persisted_entries
      hotel.hotel_discounts.reload.includes(:transaction_code, :applicable_transaction_codes).ordered.map do |discount|
        {
          "id" => discount.id.to_s,
          "client_key" => "discount-#{discount.id}",
          "name" => discount.name,
          "code" => discount.code,
          "description" => discount.description,
          "pricing_type" => discount.pricing_type,
          "rate_value" => discount.rate_value&.to_s,
          "application_scope" => discount.application_scope,
          "allow_amount_override" => discount.allow_amount_override.to_s,
          "active" => discount.active?.to_s,
          "applicable_transaction_code_ids" => discount.applicable_transaction_codes.map { |code| code.id.to_s }
        }
      end
    end

    def failure(message, section: nil)
      Result.failure(message.presence || FAILURE_MESSAGE, section: section, entries: rows)
    end
  end
end
