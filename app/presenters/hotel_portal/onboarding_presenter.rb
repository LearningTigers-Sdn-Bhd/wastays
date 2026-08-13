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
      "roles_permissions" => [ "Roles and permissions", "Review the preset access levels your team will use after launch. They are read-only during onboarding; custom role management opens after launch when the property’s plan includes it." ],
      "staff_setup" => [ "Staff setup", "Prepare team members and their roles. Nothing is sent now — invitations are created only after onboarding is successfully submitted." ],
      "taxes_fees" => [ "Taxes and fees", "Confirm statutory taxes and configure any mandatory property fees." ],
      "room_revenue" => [ "Room revenue", "Set how room sales post and which taxes and policies apply." ],
      "rooms" => [ "Rooms", "Create the room categories, capacity, amenities, policies, and room numbering this property operates. Pricing, photos, and descriptive details come later." ],
      "rates_availability" => [ "Rates and availability", "Set sell-mode pricing and establish one year of sellable inventory." ],
      "extra_charges" => [ "Extra charges", "Anything sold on top of the room — breakfast, parking, an airport transfer. Mandatory charges every guest pays belong in Taxes and fees instead." ],
      "discounts" => [ "Discounts", "Offers staff apply to a folio — an early bird rate, a staff rate, a goodwill rebate. Each one names the charges it is allowed to reduce." ],
      "payment_methods" => [ "Payment methods", "The ways guests can hand over money. At least one is needed before this property can open; card surcharges are set under Settings." ],
      "corporate_accounts" => [ "Corporate accounts", "Add corporate clients, travel agents, and airlines that book with this property. Each will be invited after you submit the property for review." ],
      "channel_manager" => [ "Channel manager", "Hand over the extranet logins for the OTAs this property sells on. The WAStays team connects each channel after approval — nothing is connected from here." ],
      "review" => [ "Review and submit", "Resolve blocking issues, review your choices, and submit the property for approval." ]
    }.freeze

    # The shell renders the action footer outside the section body, so it needs
    # to know which form each section's buttons submit. Sections absent here have
    # no form of their own and fall back to the standalone action buttons.
    # No section carries a skip button any more. An optional section either
    # answers itself — an empty table is the decision, and continuing from one
    # records it — or is required and cannot be skipped at all. See
    # docs/onboarding/DESIGN_DECISIONS.md.
    SECTION_FORMS = {
      "property_profile" => "onboarding-property-profile-form",
      "roles_permissions" => "onboarding-role-presets-form",
      "staff_setup" => "onboarding-staff-drafts-form",
      "taxes_fees" => "onboarding-taxes-fees-form",
      "room_revenue" => "onboarding-room-revenue-form",
      "rooms" => "onboarding-rooms-form",
      "rates_availability" => "onboarding-rates-availability-form",
      "extra_charges" => "onboarding-extra-charges-form",
      "discounts" => "onboarding-discounts-form",
      "payment_methods" => "onboarding-payment-methods-form",
      "corporate_accounts" => "onboarding-corporate-accounts-form",
      "channel_manager" => "onboarding-channel-manager-form",
      "review" => "onboarding-submission-form"
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
    def read_only? = Onboarding::LifecycleCompatibility.canonical_status(hotel.status).in?(%w[pending_review live])
    def review? = current_entry.definition.key == "review"
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

    def form_id = read_only? ? nil : SECTION_FORMS[current_entry.definition.key]

    # The review page has no action once submitted or approved. Other read-only
    # sections retain Back so the submitted setup can still be inspected.
    def actions?
      return false if review? && read_only?

      !read_only? || previous_entry.present?
    end

    def read_only_alert
      if Onboarding::LifecycleCompatibility.canonical_status(hotel.status) == "live"
        { tone: :success, title: "Setup approved", description: "This approved setup is read-only because the property is live." }
      else
        { tone: :info, title: "Setup submitted for review", description: "Your onboarding details are read-only while the WAStays team reviews this property." }
      end
    end

    def previous_entry = navigation.previous_entry(current_entry.definition.key)
    def next_entry = navigation.next_entry(current_entry.definition.key)

    def section_title(entry)
      SECTION_CONTENT.fetch(entry.definition.key).first
    end

    def changes_requested_message
      return unless current_entry.record.state == "needs_attention"

      # A section reaches needs_attention either because an admin asked for
      # changes or because something upstream invalidated it — both carry their
      # reason in the audit event, so both are worth showing.
      event = hotel.onboarding_audit_events
                   .where(event_type: %w[changes_requested invalidated], section_key: [ nil, current_entry.definition.key ])
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
