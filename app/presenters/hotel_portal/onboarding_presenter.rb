# frozen_string_literal: true

module HotelPortal
  class OnboardingPresenter
    Phase = Data.define(:key, :label, :entries, :state, :current)

    PHASE_LABELS = {
      "property" => "Property",
      "team" => "Team",
      "finance" => "Finance",
      "rooms_rates" => "Rooms & rates",
      "commercial" => "Commercial",
      "review" => "Review"
    }.freeze

    SECTION_CONTENT = {
      "property_profile" => [ "Property profile", "Add the identity, location, contact details, amenities, photos, and policies guests need." ],
      "roles_permissions" => [ "Roles and permissions", "Review the preset access levels your team will use after launch." ],
      "staff_setup" => [ "Staff setup", "Prepare team members and their roles without sending invitations yet." ],
      "taxes_fees" => [ "Taxes and fees", "Confirm statutory taxes and configure any mandatory property fees." ],
      "room_revenue" => [ "Room revenue", "Set how room sales post and which taxes and policies apply." ],
      "rooms" => [ "Rooms", "Create the room types, capacity, amenities, photos, and operating details you sell." ],
      "rates_availability" => [ "Rates and availability", "Set sell-mode pricing and establish one year of sellable inventory." ],
      "extra_charges" => [ "Extra charges", "Add optional products and services guests can purchase." ],
      "discounts" => [ "Discounts", "Configure the offers that can reduce eligible charges." ],
      "payment_methods" => [ "Payment methods", "Choose at least one way guests can pay and configure any surcharges." ],
      "corporate_accounts" => [ "Corporate accounts", "Prepare company accounts and invitations for submission." ],
      "channel_manager" => [ "Channel manager", "Review the preferred provider and decide whether to connect now." ],
      "review" => [ "Review and submit", "Resolve blocking issues, review your choices, and submit the property for approval." ]
    }.freeze

    def initialize(hotel:, navigation:, current_entry:)
      @hotel = hotel
      @navigation = navigation
      @current_entry = current_entry
    end

    attr_reader :hotel, :navigation, :current_entry

    def title = SECTION_CONTENT.fetch(current_entry.definition.key).first
    def description = SECTION_CONTENT.fetch(current_entry.definition.key).last
    def phase_label = PHASE_LABELS.fetch(current_entry.definition.phase)
    def required? = current_entry.definition.required
    def read_only? = Onboarding::LifecycleCompatibility.canonical_status(hotel.status) == "pending_review"
    def current_position = navigation.entries.index(current_entry) + 1
    def total_sections = navigation.entries.length

    def phases
      PHASE_LABELS.map do |key, label|
        entries = navigation.entries.select { |entry| entry.definition.phase == key }
        Phase.new(
          key: key,
          label: label,
          entries: entries,
          state: phase_state(entries),
          current: key == current_entry.definition.phase
        )
      end
    end

    def active_phase_entries
      navigation.entries.select { |entry| entry.definition.phase == current_entry.definition.phase }
    end

    def phase_position
      phases.index { |phase| phase.current } + 1
    end

    def previous_entry = navigation.previous_entry(current_entry.definition.key)
    def next_entry = navigation.next_entry(current_entry.definition.key)

    def section_title(entry)
      SECTION_CONTENT.fetch(entry.definition.key).first
    end

    def changes_requested_message
      return unless current_entry.record.state == "needs_attention"

      event = hotel.onboarding_audit_events
                   .where(event_type: "changes_requested", section_key: [ nil, current_entry.definition.key ])
                   .order(occurred_at: :desc)
                   .first
      event&.metadata&.slice("explanation", "reason")&.values&.compact&.first ||
        "Review this section and save the requested changes before continuing."
    end

    private

    def phase_state(entries)
      states = entries.map { |entry| entry.record.state }
      return "needs_attention" if states.include?("needs_attention")
      return "complete" if entries.all? { |entry| entry.record.resolved? }
      return "in_progress" if entries.any? { |entry| entry.record.state != "not_started" }

      "not_started"
    end
  end
end
