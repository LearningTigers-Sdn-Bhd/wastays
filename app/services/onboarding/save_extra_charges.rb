# frozen_string_literal: true

module Onboarding
  # The optional products and services a property sells on top of the room.
  #
  # The page arrives prefilled with a row for each seeded revenue code the
  # property has not adopted yet — F&B, Parking, Damage, Cleaning, Misc — so the
  # owner edits a real starting point instead of an empty table. Those rows are
  # unsaved until this service runs, which is what keeps provisioning a
  # deliberate act rather than a side effect of opening the page.
  #
  # Financials::EnsureDefaultExtraCharges is deliberately NOT called here. It
  # attaches a charge to every seeded code it finds unattached, so running it on
  # each save would resurrect the defaults an owner had just removed, and would
  # double up against the prefilled rows already in the submission.
  class SaveExtraCharges
    Result = ApplicationResult.define(:section, :entries)

    ENTRY_FIELDS = %w[
      id transaction_code_id client_key _destroy
      name code category description pricing_type rate_value
      charging_unit percentage_basis allow_amount_override active
    ].freeze

    DOWNSTREAM_SECTIONS = %w[discounts payment_methods].freeze

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
      return failure("Add at least one extra charge, or choose no extra charges for now.") if complete && retained_rows.empty?

      transition = nil
      before_signature = material_signature

      Hotel.transaction do
        destroy_rows!
        save_rows!

        transition = transition_section
        fail_transaction!(transition.error) unless transition.success?

        if material_signature != before_signature
          invalidation = InvalidateDependentSections.call(
            hotel: hotel,
            section_keys: DOWNSTREAM_SECTIONS,
            actor: actor,
            source: "extra_charge_change",
            explanation: "The extra charges this property sells changed. Check that discounts and payment surcharges still point at the charges you want.",
            invalidated_by: "extra_charges"
          )
          fail_transaction!(invalidation.error) unless invalidation.success?
        end
      end

      return failure(@error) if @error.present?

      Result.success(section: transition.section, entries: persisted_entries)
    rescue ActiveRecord::RecordNotFound
      failure("One or more submitted extra charges do not belong to this property.")
    end

    private

    attr_reader :hotel, :actor, :complete

    # --- persistence --------------------------------------------------------

    def destroy_rows!
      discarded_rows.each do |row|
        charge = existing_charges.fetch(row["id"].to_s)
        blocker = surcharge_blocker(charge)
        fail_transaction!("#{charge_name(charge)} cannot be removed because the #{blocker} payment method adds it as a surcharge.") if blocker

        charge.destroy!
      end
    end

    def save_rows!
      retained_rows.each_with_index do |row, index|
        charge = build_or_find_charge(row)
        result = ExtraCharges::Save.call(
          extra_charge: charge,
          attributes: row.slice(*ENTRY_FIELDS).merge("position" => index),
          tax_rule_keys: row["tax_rule_keys"]
        )
        next if result.success?

        fail_transaction!("Extra charge #{index + 1}: #{result.extra_charge.errors.full_messages.to_sentence}")
      end
    end

    # Three ways a row arrives: an extra charge this property already has, a
    # seeded revenue code being adopted for the first time (the prefilled rows),
    # or something the owner typed from scratch.
    #
    # New records are built off the class rather than the association, so a
    # rolled-back batch does not leave unsaved rows sitting in the caller's
    # hotel.hotel_extra_charges collection.
    def build_or_find_charge(row)
      return existing_charges.fetch(row["id"].to_s) if row["id"].present?
      return HotelExtraCharge.new(hotel: hotel, transaction_code: adoptable_codes.fetch(row["transaction_code_id"].to_s)) if row["transaction_code_id"].present?

      HotelExtraCharge.new(
        hotel: hotel,
        transaction_code: TransactionCode.new(
          hotel: hotel, kind: "charge", category: "other", active: true, system_required: false
        )
      )
    end

    def surcharge_blocker(charge)
      HotelPaymentMethod.where(surcharge_extra_charge_id: charge.id)
                        .includes(:transaction_code).first&.name
    end

    def charge_name(charge) = charge.name.presence || "This extra charge"

    # --- validation ---------------------------------------------------------

    def foreign_reference_error
      return @foreign_reference_error if defined?(@foreign_reference_error)

      submitted_ids = rows.filter_map { |row| row["id"].presence&.to_s }
      submitted_codes = retained_rows.filter_map { |row| row["transaction_code_id"].presence&.to_s }

      @foreign_reference_error =
        if submitted_ids.any? { |id| !existing_charges.key?(id) } ||
           submitted_codes.any? { |id| !adoptable_codes.key?(id) }
          "One or more submitted extra charges do not belong to this property."
        end
    end

    # Two codes that normalize alike pass their own row's validation and then
    # collide on the per-hotel unique index, which would surface as a 500 rather
    # than something the owner can act on.
    def duplicate_code_error
      return @duplicate_code_error if defined?(@duplicate_code_error)

      codes = retained_rows.map { |row| normalize_code(row["code"]) }.reject(&:blank?)
      duplicate = codes.tally.find { |_code, count| count > 1 }&.first
      @duplicate_code_error = ("Extra charge codes must be unique. #{duplicate} is used more than once." if duplicate)
    end

    def normalize_code(value)
      value.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    end

    # --- section transition -------------------------------------------------

    def transition_section
      UpdateSection.new(
        hotel: hotel,
        section_key: "extra_charges",
        state: complete ? "complete" : "in_progress",
        actor: actor,
        metadata: { source: "extra_charge_setup", extra_charge_count: hotel.hotel_extra_charges.reload.size }
      ).call
    end

    # What downstream setup actually depends on: which charges exist and whether
    # they can be posted. Renaming one does not invalidate anything.
    def material_signature
      hotel.hotel_extra_charges.joins(:transaction_code).order(:id).pluck(:id, "transaction_codes.active")
    end

    # --- entries ------------------------------------------------------------

    def rows
      @rows ||= normalize_collection(@entries).map do |row|
        row.slice(*ENTRY_FIELDS, "tax_rule_keys")
      end
    end

    def retained_rows
      @retained_rows ||= rows.reject { |row| discarded?(row) || blank_row?(row) }
    end

    def discarded_rows
      @discarded_rows ||= rows.select { |row| discarded?(row) && row["id"].present? }
    end

    def discarded?(row) = ActiveModel::Type::Boolean.new.cast(row["_destroy"])
    def blank_row?(row) = row["id"].blank? && row["name"].to_s.strip.blank? && row["code"].to_s.strip.blank?

    def normalize_collection(value)
      collection = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.values : (value.is_a?(Hash) ? value.values : Array(value))
      collection.map { |item| (item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h).deep_stringify_keys }
    end

    def existing_charges
      @existing_charges ||= hotel.hotel_extra_charges.includes(:transaction_code).index_by { |charge| charge.id.to_s }
    end

    # Only the seeded revenue codes Financials::EnsureDefaultExtraCharges would
    # itself adopt, and only while nothing has claimed them — one extra charge
    # per code. Room revenue and the cancellation codes are deliberately out of
    # reach: they are posted by the booking engine, not sold as extras.
    def adoptable_codes
      @adoptable_codes ||= hotel.transaction_codes
                                .where(system_key: Financials::EnsureDefaultExtraCharges::SYSTEM_KEYS)
                                .where.missing(:hotel_extra_charge)
                                .index_by { |code| code.id.to_s }
    end

    def persisted_entries
      hotel.hotel_extra_charges.reload.includes(transaction_code: :transaction_code_taxes).ordered.map do |charge|
        {
          "id" => charge.id.to_s,
          "client_key" => "extra-charge-#{charge.id}",
          "name" => charge.name,
          "code" => charge.code,
          "category" => charge.category,
          "description" => charge.description,
          "pricing_type" => charge.pricing_type,
          "rate_value" => charge.rate_value&.to_s,
          "charging_unit" => charge.charging_unit,
          "percentage_basis" => charge.percentage_basis,
          "allow_amount_override" => charge.allow_amount_override.to_s,
          "active" => charge.active?.to_s,
          "tax_rule_keys" => charge.transaction_code.tax_rule_keys
        }
      end
    end

    def fail_transaction!(message)
      @error = message.presence || "Extra charges could not be saved."
      raise ActiveRecord::Rollback
    end

    def failure(message, section: nil)
      Result.failure(message.presence || "Extra charges could not be saved.", section: section, entries: rows)
    end
  end
end
