# frozen_string_literal: true

module Onboarding
  class Readiness
    Finding = Data.define(:section_key, :severity, :code, :message)
    Result = Data.define(:ready, :blocking_issues, :warnings)

    def initialize(hotel:, rates_coverage: nil)
      @hotel = hotel
      @rates_coverage = rates_coverage
    end

    def call
      InitializeProgress.new(hotel: @hotel).call if @hotel.onboarding_sections.size < SectionCatalog.keys.size
      states = @hotel.onboarding_sections.index_by(&:section_key)
      blocking = []
      warnings = []

      SectionCatalog.all.reject { |section| section.key == "review" }.each do |section|
        record = states.fetch(section.key)
        if record.state == "needs_attention"
          blocking << finding(section.key, :needs_attention, "Review the requested changes in this section.")
        elsif record.decision_metadata["placeholder"]
          blocking << finding(section.key, :placeholder, "This section still contains unfinished setup.")
        elsif section.required && record.state != "complete"
          blocking << finding(section.key, :required_incomplete, "Complete this required section.")
        elsif !section.required && !record.resolved?
          blocking << finding(section.key, :decision_missing, "Finish this section or record that there is nothing to add for now.")
        elsif record.state == "skipped"
          warnings << Finding.new(section_key: section.key, severity: :warning, code: :deferred, message: "Nothing was added in this optional section.")
        end
      end

      add_domain_findings(blocking, states)

      Result.new(ready: blocking.empty?, blocking_issues: blocking.freeze, warnings: warnings.freeze)
    end

    private

    def finding(section_key, code, message)
      Finding.new(section_key:, severity: :blocking, code:, message:)
    end

    def add_domain_findings(blocking, states)
      add_once(blocking, "property_profile", :property_invalid, "Add the required property details.") unless @hotel.property_profile_ready?
      add_once(blocking, "property_photos", :photos_missing, "Upload at least one photo of the property.") unless @hotel.property_photos_ready?
      add_once(blocking, "roles_permissions", :roles_changed, "Review and confirm all four standard roles again.") unless role_confirmation_current?(states)
      add_once(blocking, "staff_setup", :staff_decision_missing, "Confirm the staff to invite, or record that there are no additional staff.") unless explicit_decision?(states, "staff_setup", "staff_draft_setup")
      add_once(blocking, "taxes_fees", :tax_confirmation_stale, "Review and confirm the property's current taxes and fees.") unless taxes_ready?(states)
      add_once(blocking, "room_revenue", :room_revenue_invalid, "Confirm the room revenue posting and tax rules.") unless room_revenue_ready?
      add_once(blocking, "rooms", :rooms_invalid, "Add at least one operationally valid room type.") unless rooms_ready?
      add_once(blocking, "rates_availability", :coverage_incomplete, "Complete one year of sellable rates and availability.") unless rates_coverage.complete?
      add_once(blocking, "payment_methods", :payment_method_missing, "Add at least one active payment method.") unless @hotel.hotel_payment_methods.active.exists?
      optional_sources.each do |section_key, source|
        add_once(blocking, section_key, :decision_missing, "Review this section and record the property's decision.") unless explicit_decision?(states, section_key, source)
      end
    end

    def add_once(blocking, section_key, code, message)
      return if blocking.any? { |item| item.section_key == section_key }

      blocking << finding(section_key, code, message)
    end

    def role_confirmation_current?(states)
      metadata = states.fetch("roles_permissions").decision_metadata
      roles = @hotel.account.roles.where(slug: ConfirmRolePresets::PRESET_SLUGS).includes(:permissions).to_a
      return false unless roles.size == ConfirmRolePresets::PRESET_SLUGS.size

      current = ConfirmRolePresets.permission_fingerprint(roles)
      metadata["permission_fingerprint"] == current
    end

    def room_revenue_ready?
      section = @hotel.onboarding_sections.find_by(section_key: "room_revenue")
      TransactionCodes::Resolver.for(@hotel).room_revenue.present? &&
        @hotel.hotel_transaction_configuration.present? &&
        section&.decision_metadata&.fetch("tax_fingerprint", nil) == TaxFingerprint.call(@hotel)
    end

    def rooms_ready?
      rooms = @hotel.room_types.to_a
      rooms.any? && rooms.all? { |room| room.valid? && room.quantity.positive? }
    end

    def taxes_ready?(states)
      metadata = states.fetch("taxes_fees").decision_metadata
      return false unless metadata["confirmed"] == true
      return false unless metadata["custom_tax_count"] == @hotel.hotel_taxes.size
      return false if @hotel.hotel_taxes.any?(&:invalid?)
      return false if @hotel.tourism_tax_enabled? && @hotel.tourism_tax_amount.to_d <= 0

      true
    end

    def explicit_decision?(states, section_key, source)
      states.fetch(section_key).decision_metadata["source"] == source
    end

    def optional_sources
      {
        "extra_charges" => "extra_charge_setup",
        "discounts" => "discount_setup",
        "corporate_accounts" => "corporate_account_setup",
        "channel_manager" => "channel_manager_setup"
      }
    end

    def rates_coverage
      @rates_coverage ||= Rates::SetupCoverage.call(hotel: @hotel)
    end
  end
end
