# frozen_string_literal: true

module Onboarding
  class SnapshotSummaryPresenter
    Row = Data.define(:definition, :title, :summary, :status_label, :status_variant)
    Group = Data.define(:key, :label, :rows)

    STATE_LABELS = {
      "not_started" => "Not started",
      "in_progress" => "In progress",
      "complete" => "Complete",
      "skipped" => "Deferred",
      "needs_attention" => "Needs attention"
    }.freeze
    STATE_VARIANTS = {
      "not_started" => :neutral,
      "in_progress" => :info,
      "complete" => :success,
      "skipped" => :warning,
      "needs_attention" => :destructive
    }.freeze

    def initialize(snapshot:)
      @snapshot = snapshot.to_h.deep_stringify_keys
    end

    attr_reader :snapshot

    def groups
      HotelPortal::OnboardingPresenter::PHASE_LABELS.except("review").map do |key, label|
        definitions = SectionCatalog.all.select { |definition| definition.phase == key }
        Group.new(key:, label:, rows: definitions.map { |definition| row_for(definition) })
      end
    end

    private

    def row_for(definition)
      state = snapshot.dig("sections", definition.key, "state")
      state = "not_started" unless STATE_LABELS.key?(state)

      Row.new(
        definition:,
        title: HotelPortal::OnboardingPresenter::SECTION_CONTENT.fetch(definition.key).first,
        summary: summary_for(definition.key),
        status_label: STATE_LABELS.fetch(state),
        status_variant: STATE_VARIANTS.fetch(state)
      )
    end

    def summary_for(section_key)
      case section_key
      when "property_profile" then property_summary
      when "roles_permissions" then "#{ConfirmRolePresets::PRESET_SLUGS.size} standard roles confirmed"
      when "staff_setup" then count_summary(snapshot["staff"], "staff member", "No additional staff")
      when "taxes_fees"
        count_summary(snapshot["taxes"], "property tax or fee", "No additional property fees", plural: "property taxes or fees")
      when "room_revenue" then "Posting and tax rules confirmed"
      when "rooms" then rooms_summary
      when "rates_availability" then rates_summary
      when "extra_charges" then count_summary(commercial["extra_charges"], "extra charge", "No extra charges")
      when "discounts" then count_summary(commercial["discounts"], "discount", "No discounts")
      when "payment_methods" then count_summary(commercial["payment_methods"], "payment method", "No payment methods")
      when "corporate_accounts" then count_summary(commercial["corporate_accounts"], "corporate account", "No corporate accounts")
      when "channel_manager" then count_summary(snapshot["ota_handover"], "channel handover", "No channel handover")
      end
    end

    def property_summary
      property = snapshot.fetch("property", {})
      location = [ property["city"], property["country"] ].compact_blank.join(", ")
      [ location.presence, property["default_currency"].presence ].compact.join(" · ").presence || "Property details saved"
    end

    def rooms_summary
      rooms = Array(snapshot["rooms"])
      total = rooms.sum { |room| room["quantity"].to_i }
      "#{rooms.size} #{'room type'.pluralize(rooms.size)} · #{total} #{'room'.pluralize(total)}"
    end

    def rates_summary
      value = snapshot.dig("rates", "coverage", "end_date")
      return "Rate coverage saved" if value.blank?

      "Coverage through #{I18n.l(Date.iso8601(value), format: '%d %b %Y')}"
    rescue Date::Error
      "Rate coverage saved"
    end

    def count_summary(rows, noun, empty, plural: nil)
      count = Array(rows).size
      return empty if count.zero?

      "#{count} #{count == 1 ? noun : (plural || noun.pluralize)}"
    end

    def commercial = snapshot.fetch("commercial", {})
  end
end
