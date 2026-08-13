# frozen_string_literal: true

module Onboarding
  # Taxes and fees: the statutory taxes the property charges, plus any mandatory
  # fees of its own.
  #
  # System taxes are hotel columns but are written through TaxSettingsForm, never
  # directly — the form is what re-syncs the SST/tourism transaction codes' active
  # flag when the toggles change (Hotel#sync_primary_tax_transaction_codes looks
  # like it does this, but nothing wires it up). A direct column write would leave
  # the posting codes stale.
  #
  # Completion is an explicit confirmation rather than a successful save: the
  # owner is asserting these are the taxes their property charges, which is not
  # something visiting the page can establish on their behalf.
  class SaveTaxesFees
    Result = ApplicationResult.define(:section, :entries)

    ENTRY_FIELDS = %w[id name charge_type rate_type amount enabled foreign_guests_only].freeze

    def initialize(hotel:, actor:, params:, confirmed:, complete:)
      @hotel = hotel
      @actor = actor
      @params = params
      @confirmed = ActiveModel::Type::Boolean.new.cast(confirmed)
      @complete = complete
    end

    def call
      return failure(tourism_amount_error) if tourism_amount_error.present?
      return failure(removal_error) if removal_error.present?

      transition_result = nil
      @error = nil

      Hotel.transaction do
        Financials::EnsureDefaultTransactionCodes.call(@hotel)

        unless save_system_taxes
          @error = @hotel.errors.full_messages.to_sentence.presence || "Tax settings could not be saved."
          raise ActiveRecord::Rollback
        end

        unless apply_entries
          raise ActiveRecord::Rollback
        end

        if @complete && !@confirmed
          @error = "Confirm that you reviewed the taxes and fees this property charges."
          raise ActiveRecord::Rollback
        end

        transition_result = UpdateSection.new(
          hotel: @hotel,
          section_key: "taxes_fees",
          state: @complete ? "complete" : "in_progress",
          actor: @actor,
          metadata: {
            source: "tax_confirmation",
            confirmed: @confirmed,
            custom_tax_count: @hotel.hotel_taxes.reload.size,
            tax_fingerprint: TaxFingerprint.call(@hotel)
          }
        ).call
        raise ActiveRecord::Rollback unless transition_result.success?
      end

      return failure(@error) if @error.present?
      return failure(transition_result.error, section: transition_result.section) unless transition_result&.success?

      InvalidateRoomRevenue.call(hotel: @hotel, actor: @actor)

      Result.success(section: transition_result.section, entries: persisted_entries)
    end

    private

    def failure(message, section: nil)
      Result.failure(message, section: section, entries: submitted_entries.presence || persisted_entries)
    end

    # --- system taxes -------------------------------------------------------

    def save_system_taxes
      HotelPortal::TaxSettingsForm.new(
        @hotel,
        ActionController::Parameters.new(hotel: system_tax_attributes)
      ).save
    end

    def system_tax_attributes
      source = @params[:hotel] || {}
      source = source.to_unsafe_h if source.respond_to?(:to_unsafe_h)
      source = source.to_h.stringify_keys

      {
        "sst_enabled" => boolean(source["sst_enabled"]),
        "tourism_tax_enabled" => boolean(source["tourism_tax_enabled"]),
        "tourism_tax_amount" => source.fetch("tourism_tax_amount", @hotel.tourism_tax_amount)
      }
    end

    # The model validates nothing here, so an empty or negative amount would save
    # and quietly post as zero on every foreign booking.
    def tourism_amount_error
      return @tourism_amount_error if defined?(@tourism_amount_error)

      @tourism_amount_error = compute_tourism_amount_error
    end

    def compute_tourism_amount_error
      return unless boolean(system_tax_attributes["tourism_tax_enabled"])

      amount = system_tax_attributes["tourism_tax_amount"]
      return "Enter the tourism tax amount charged per night." if amount.to_s.strip.blank?

      value = BigDecimal(amount.to_s, exception: false)
      return "Enter a valid tourism tax amount." if value.nil?
      return "Tourism tax amount cannot be negative." if value.negative?

      nil
    end

    # --- custom taxes and fees ---------------------------------------------

    def submitted_entries
      @submitted_entries ||= begin
        raw = @params[:tax_entries]
        collection = if raw.respond_to?(:to_unsafe_h)
                       raw.to_unsafe_h.values
        elsif raw.is_a?(Hash)
                       raw.values
        else
                       Array(raw)
        end

        collection.filter_map do |entry|
          values = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry.to_h
          normalized = values.stringify_keys.slice(*ENTRY_FIELDS).transform_values { |value| value.to_s.strip }
          normalized unless normalized.except("id", "charge_type", "rate_type", "enabled", "foreign_guests_only").values.all?(&:blank?)
        end
      end
    end

    def persisted_entries
      @hotel.hotel_taxes.order(:created_at, :id).map do |tax|
        {
          "id" => tax.id.to_s,
          "name" => tax.name,
          "charge_type" => tax.charge_type,
          "rate_type" => tax.rate_type,
          "amount" => tax.amount.to_s,
          "enabled" => tax.enabled.to_s,
          "foreign_guests_only" => tax.foreign_guests_only.to_s
        }
      end
    end

    def submitted_ids
      @submitted_ids ||= submitted_entries.filter_map { |entry| entry["id"].presence }
    end

    def removed_taxes
      @removed_taxes ||= @hotel.hotel_taxes.where.not(id: submitted_ids).to_a
    end

    # Removing a tax that room revenue assigns would cascade its rule away and
    # silently change how every room night is taxed. Ask the owner to unassign it
    # first rather than doing that behind them.
    def removal_error
      return @removal_error if defined?(@removal_error)

      @removal_error = compute_removal_error
    end

    def compute_removal_error
      assigned = removed_taxes.select { |tax| tax.transaction_code_taxes.exists? }
      return if assigned.empty?

      names = assigned.map(&:name).to_sentence
      "Remove #{names} from the room revenue tax rules before deleting it."
    end

    def apply_entries
      removed_taxes.each(&:destroy!)

      submitted_entries.each_with_index do |entry, index|
        tax = entry["id"].present? ? @hotel.hotel_taxes.find_by(id: entry["id"]) : @hotel.hotel_taxes.build
        next if tax.blank?

        tax.assign_attributes(
          name: entry["name"],
          charge_type: charge_type_for(entry, tax),
          rate_type: HotelTax::RATE_TYPES.include?(entry["rate_type"]) ? entry["rate_type"] : "flat",
          amount: entry["amount"],
          enabled: enabled_for(entry, tax),
          foreign_guests_only: boolean(entry["foreign_guests_only"])
        )

        next if tax.save

        @error = "Row #{index + 1}: #{tax.errors.full_messages.to_sentence}"
        return false
      end

      true
    end

    # Onboarding does not ask whether a tax is levied — listing it is the answer,
    # and removing the row is how it is unlisted. A row that reaches here is
    # charged. Settings still owns the toggle, so a tax retired there keeps its
    # state when onboarding is revisited rather than being switched back on.
    def enabled_for(entry, tax)
      return boolean(entry["enabled"]) if entry.key?("enabled")
      return tax.enabled? if tax.persisted?

      true
    end

    # "others" is a legacy value the UI renders as Fee; preserve it on rows that
    # already carry it rather than silently rewriting their charge type.
    def charge_type_for(entry, tax)
      submitted = entry["charge_type"]
      return submitted if HotelTax::CHARGE_TYPES.include?(submitted)
      return tax.charge_type if tax.persisted? && tax.charge_type.present?

      "tax"
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value).present?
    end
  end
end
