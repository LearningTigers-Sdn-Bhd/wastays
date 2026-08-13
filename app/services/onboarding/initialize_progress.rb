# frozen_string_literal: true

module Onboarding
  class InitializeProgress
    def initialize(hotel:, actor: nil)
      @hotel = hotel
      @actor = actor
    end

    def call
      HotelOnboardingSection.transaction do
        SectionCatalog.keys.each do |section_key|
          @hotel.onboarding_sections.find_or_create_by!(section_key: section_key)
        end

        unless @hotel.onboarding_audit_events.exists?(event_type: "initialized")
          @hotel.onboarding_audit_events.create!(
            user: @actor,
            event_type: "initialized",
            occurred_at: Time.current
          )
        end
      end

      @hotel.onboarding_sections.in_journey_order
    end
  end
end
