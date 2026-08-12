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
    include CommercialRows

    Result = ApplicationResult.define(:section, :entries)

    # Onboarding asks for four things: what the charge is called, what it costs,
    # how it is counted, and what tax it carries. Everything else the record
    # holds is either derived from those or kept as it stands — the settings
    # portal is where the full editor lives, and a table that does not show a
    # field must not quietly rewrite it.
    ENTRY_FIELDS = %w[
      id transaction_code_id client_key _destroy
      name code rate_value charging_unit tax_rule_keys
    ].freeze

    RECORD_LABEL = "Extra charge"
    FAILURE_MESSAGE = "Extra charges could not be saved."
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
          attributes: charge_attributes(charge, row, index),
          tax_rule_keys: row["tax_rule_keys"]
        )
        next if result.success?

        fail_transaction!(row_error(index, result.extra_charge.errors.full_messages.to_sentence))
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

    # The four submitted fields, plus what the record already says about
    # everything the table leaves out. Category, description and whether the
    # charge is offered all come off the record, so a charge configured in the
    # settings portal survives a pass through onboarding unchanged.
    def charge_attributes(charge, row, index)
      {
        "name" => row["name"],
        "code" => row["code"].presence || charge.code,
        "category" => charge.transaction_code.category.presence || "other",
        "description" => charge.description,
        "charging_unit" => row["charging_unit"].presence || "per_item",
        "active" => charge.active?.to_s,
        "position" => index
      }.merge(pricing_attributes(charge, row))
    end

    # One price field stands in for the pricing method: an amount means a fixed
    # price, and leaving it empty means staff decide when they post it.
    #
    # Percentage pricing has no square to type it in, so a charge already set
    # that way in the settings portal keeps its rate and basis rather than being
    # flattened into a fixed amount by a table that cannot express it.
    def pricing_attributes(charge, row)
      if charge.persisted? && charge.percentage?
        return {
          "pricing_type" => "percentage",
          "rate_value" => charge.rate_value,
          "percentage_basis" => charge.percentage_basis
        }
      end

      price = row["rate_value"].to_s.strip
      {
        "pricing_type" => price.present? ? "fixed" : "manual",
        "rate_value" => price.presence,
        "allow_amount_override" => (charge.persisted? ? charge.allow_amount_override : true).to_s
      }
    end

    def surcharge_blocker(charge)
      HotelPaymentMethod.where(surcharge_extra_charge_id: charge.id)
                        .includes(:transaction_code).first&.name
    end

    def charge_name(charge) = charge.name.presence || "This extra charge"

    # --- codes --------------------------------------------------------------

    # An owner setting the property up is naming what they sell, not keeping the
    # books, so the table does not ask for an accounting code. A row typed from
    # scratch gets one derived from its name here rather than at save time, so
    # the duplicate check and the unique index both see the value that will be
    # stored. Rows that already have a code — an adopted revenue code, or a
    # charge the property saved earlier — carry it through untouched.
    def prepare_row(row)
      return row if row["id"].present? || row["transaction_code_id"].present?
      return row if row["code"].to_s.strip.present? || row["name"].to_s.strip.blank? || discarded?(row)

      row.merge("code" => generated_code(row["name"]))
    end

    def generated_code(name)
      base = normalize_code(name).first(10).delete_suffix("_").presence || "CHARGE"
      candidate = base
      suffix = 2

      while claimed_codes.include?(candidate)
        candidate = "#{base.first(9 - suffix.to_s.length).delete_suffix('_')}_#{suffix}"
        suffix += 1
      end

      claimed_codes << candidate
      candidate
    end

    def claimed_codes
      @claimed_codes ||= hotel.transaction_codes.pluck(:code).map { |code| normalize_code(code) }.to_set
    end

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
          "rate_value" => (charge.rate_value&.to_s unless charge.percentage?),
          "charging_unit" => charge.charging_unit,
          "tax_rule_keys" => charge.transaction_code.tax_rule_keys
        }
      end
    end

    def failure(message, section: nil)
      Result.failure(message.presence || FAILURE_MESSAGE, section: section, entries: rows)
    end
  end
end
