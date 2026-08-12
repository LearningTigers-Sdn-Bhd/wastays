# frozen_string_literal: true

module Onboarding
  # How guests can pay. The only required section of the commercial phase: a
  # property with no way to take money cannot open, so this one has no skip.
  #
  # Like its siblings the page offers the seeded payment codes as unsaved rows
  # rather than provisioning them on render or resurrecting them on every save.
  class SavePaymentMethods
    include CommercialRows

    Result = ApplicationResult.define(:section, :entries)

    ENTRY_FIELDS = %w[
      id transaction_code_id client_key _destroy
      name code payment_method_type guest_advance default_cash active
      surcharge_enabled surcharge_posting_type surcharge_value surcharge_extra_charge_id
    ].freeze

    RECORD_LABEL = "Payment method"
    FAILURE_MESSAGE = "Payment methods could not be saved."

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
      return failure(default_cash_error) if default_cash_error.present?

      transition = nil

      Hotel.transaction do
        # Taken once for the batch. PaymentMethods::Save locks the hotel row per
        # call to demote the previous default cash method; holding it here means
        # one lock for the whole submission instead of one per row.
        hotel.with_lock do
          destroy_rows!
          save_rows!

          fail_transaction!(completion_error) if complete && completion_error.present?

          transition = transition_section
          fail_transaction!(transition.error) unless transition.success?
        end
      end

      return failure(@error) if @error.present?

      Result.success(section: transition.section, entries: persisted_entries)
    rescue ActiveRecord::RecordNotFound
      failure("One or more submitted payment methods do not belong to this property.")
    end

    private

    attr_reader :hotel, :actor, :complete

    def destroy_rows!
      discarded_rows.each do |row|
        method = existing_methods.fetch(row["id"].to_s)
        fail_transaction!("#{method.name} is the default cash method. Make another cash method the default before removing it.") if method.default_cash?

        method.destroy!
      end
    end

    def save_rows!
      retained_rows.each_with_index do |row, index|
        method = build_or_find_method(row)
        method.position = index

        result = PaymentMethods::Save.call(payment_method: method, attributes: row)
        next if result.success?

        fail_transaction!(row_error(index, result.error))
      end
    end

    def build_or_find_method(row)
      return existing_methods.fetch(row["id"].to_s) if row["id"].present?
      return HotelPaymentMethod.new(hotel: hotel, transaction_code: adoptable_codes.fetch(row["transaction_code_id"].to_s)) if row["transaction_code_id"].present?

      HotelPaymentMethod.new(
        hotel: hotel,
        transaction_code: TransactionCode.new(
          hotel: hotel, kind: "payment", category: "gateway_payment", active: true, system_required: false
        )
      )
    end

    # --- validation ---------------------------------------------------------

    def foreign_reference_error
      return @foreign_reference_error if defined?(@foreign_reference_error)

      submitted_ids = rows.filter_map { |row| row["id"].presence&.to_s }
      submitted_codes = retained_rows.filter_map { |row| row["transaction_code_id"].presence&.to_s }
      submitted_charges = retained_rows.filter_map { |row| row["surcharge_extra_charge_id"].presence&.to_s if surcharge?(row) }

      @foreign_reference_error =
        if submitted_ids.any? { |id| !existing_methods.key?(id) } ||
           submitted_codes.any? { |id| !adoptable_codes.key?(id) } ||
           submitted_charges.any? { |id| !surchargeable_charge_ids.include?(id) }
          "One or more submitted payment methods do not belong to this property."
        end
    end

    # A partial unique index allows one default cash method per hotel, and
    # PaymentMethods::Save demotes the others as it goes — so two rows both
    # claiming it would silently resolve to whichever saved last.
    def default_cash_error
      claimed = retained_rows.count { |row| boolean(row["default_cash"]) }
      "Choose a single default cash method." if claimed > 1
    end

    def completion_error
      return "Activate at least one payment method guests can pay with." if hotel.hotel_payment_methods.reload.active.none?

      cash = hotel.hotel_payment_methods.active.select { |method| method.cash? && !method.guest_advance? }
      return "Choose which cash method is the default." if cash.any? && cash.none?(&:default_cash?)

      nil
    end

    def surcharge?(row) = ActiveModel::Type::Boolean.new.cast(row["surcharge_enabled"])
    def boolean(value) = ActiveModel::Type::Boolean.new.cast(value)

    # --- section transition -------------------------------------------------

    def transition_section
      UpdateSection.new(
        hotel: hotel,
        section_key: "payment_methods",
        state: complete ? "complete" : "in_progress",
        actor: actor,
        metadata: {
          source: "payment_method_setup",
          payment_method_count: hotel.hotel_payment_methods.reload.size,
          active_count: hotel.hotel_payment_methods.active.count
        }
      ).call
    end

    # --- lookups ------------------------------------------------------------

    def existing_methods
      @existing_methods ||= hotel.hotel_payment_methods.includes(:transaction_code).index_by { |method| method.id.to_s }
    end

    def adoptable_codes
      @adoptable_codes ||= hotel.transaction_codes
                                .where(system_key: PaymentMethods::EnsureDefaults::SYSTEM_KEYS)
                                .where.missing(:hotel_payment_method)
                                .index_by { |code| code.id.to_s }
    end

    def surchargeable_charge_ids
      @surchargeable_charge_ids ||= hotel.hotel_extra_charges.active.pluck(:id).map(&:to_s).to_set
    end

    def persisted_entries
      hotel.hotel_payment_methods.reload.includes(:transaction_code).ordered.map do |method|
        {
          "id" => method.id.to_s,
          "client_key" => "payment-method-#{method.id}",
          "name" => method.name,
          "code" => method.code,
          "payment_method_type" => method.payment_method_type,
          "guest_advance" => method.guest_advance.to_s,
          "default_cash" => method.default_cash.to_s,
          "active" => method.active?.to_s,
          "surcharge_enabled" => method.surcharge?.to_s,
          "surcharge_posting_type" => method.surcharge_posting_type,
          "surcharge_value" => method.surcharge_value&.to_s,
          "surcharge_extra_charge_id" => method.surcharge_extra_charge_id&.to_s
        }
      end
    end

    def failure(message, section: nil)
      Result.failure(message.presence || FAILURE_MESSAGE, section: section, entries: rows)
    end
  end
end
