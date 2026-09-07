# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class OverviewPresenter
      State = Data.define(:label, :tone)

      READY = "Ready"
      NEEDS_ATTENTION = "Needs attention"

      def initialize(hotel:)
        @hotel = hotel
      end

      # The Settings navigation asks every presenter for its settings page.
      # Guest Content has none, so it answers with nil.
      def active_page
        nil
      end

      # Each section carries its own key. The view reads the key instead of
      # pairing sections with a separate list of paths by position.
      def sections
        @sections ||= [
          section(:general_info, "Hotel Info", "info", hotel_information_state, hotel_information_detail),
          section(:policy, "Policies", "shield-check", knowledge_state("policy"), knowledge_detail("policy")),
          section(:faq, "FAQs", "message-circle-question-mark", knowledge_state("faq"), knowledge_detail("faq")),
          section(:amenity, "Amenities", "concierge-bell", amenities_state, amenities_detail),
          section(:wifi, "Wi-Fi", "wifi", wifi_state, wifi_detail),
          section(:contact, "Contact & Escalation", "phone", contact_state, contact_detail)
        ]
      end

      def ready_sections_count
        sections.count { |section| section[:status].label == READY }
      end

      def sections_count
        sections.size
      end

      def all_sections_ready?
        ready_sections_count == sections_count
      end

      def knowledge_documents_count
        @knowledge_documents_count ||= knowledge_documents.count
      end

      def open_questions_count
        @open_questions_count ||= hotel.knowledge_diagnostics.open.count
      end

      def ai_state
        return @ai_state if defined?(@ai_state)

        @ai_state = compute_ai_state
      end

      def recent_questions
        @recent_questions ||= hotel.knowledge_diagnostics.open.recent_first.limit(5)
      end

      private

      attr_reader :hotel

      def section(key, name, icon, status, detail)
        { key: key, name: name, icon: icon, status: status, detail: detail }
      end

      def compute_ai_state
        return state(NEEDS_ATTENTION, :warning) unless hotel.ai_concierge_ready?
        return state(NEEDS_ATTENTION, :warning) if knowledge_documents.failed.exists?
        return state("Updating", :neutral) if knowledge_documents.where(embedding_status: %w[pending indexing]).exists?

        state(READY, :success)
      end

      def hotel_information_state
        ready = property_summary_ready? && arrival_instructions.present? && departure_instructions.present?
        ready ? state(READY, :success) : state(NEEDS_ATTENTION, :warning)
      end

      def hotel_information_detail
        missing = []
        missing << "property summary" unless property_summary_ready?
        missing << "arrival instructions" if arrival_instructions.blank?
        missing << "departure instructions" if departure_instructions.blank?

        missing.any? ? "Add #{missing.to_sentence}." : "Property summary and stay instructions are ready."
      end

      def property_summary_ready?
        required = [ hotel.name, hotel.description, hotel.city, hotel.country ]
        required.all?(&:present?) && contact_present?
      end

      def arrival_instructions
        hotel.guest_instruction&.arrival_instructions
      end

      def departure_instructions
        hotel.guest_instruction&.departure_instructions
      end

      def contact_present?
        [ hotel.contact_email, hotel.contact_phone, hotel.whatsapp_number ].any?(&:present?)
      end

      # A guest the concierge cannot help needs a number that rings and a number
      # for an emergency. Both, or the section is not ready.
      def contact_state
        front_desk_phone.present? && emergency_number.present? ? state(READY, :success) : state(NEEDS_ATTENTION, :warning)
      end

      def contact_detail
        missing = []
        missing << "a front desk phone" if front_desk_phone.blank?
        missing << "an emergency number" if emergency_number.blank?

        missing.any? ? "Add #{missing.to_sentence}." : "Guests can reach a person and an emergency line."
      end

      def guest_contact = hotel.guest_contact

      def front_desk_phone
        guest_contact&.front_desk_phone.presence || hotel.contact_phone.presence
      end

      def emergency_number
        guest_contact&.emergency_phone.presence || guest_contact&.emergency_services_number.presence
      end

      def knowledge_state(category)
        documents = knowledge_documents.where(category: category)
        return state(NEEDS_ATTENTION, :warning) if documents.none? || documents.failed.exists?
        return state("Updating", :neutral) if documents.where(embedding_status: %w[pending indexing]).exists?

        state(READY, :success)
      end

      def knowledge_detail(category)
        count = knowledge_documents.where(category: category).count
        ActionController::Base.helpers.pluralize(count, category == "faq" ? "FAQ collection" : "policy")
      end

      def amenities_state
        hotel.amenities.any? ? state(READY, :success) : state(NEEDS_ATTENTION, :warning)
      end

      # Counts rows that carry content, not rows that exist. A saved row with
      # every field blank tells a guest nothing, and the Amenities table calls
      # it Not started.
      def amenities_detail
        rows = AmenityRow.build(hotel: hotel, amenities: Amenity.hotel.where(slug: hotel.amenities))
        "#{rows.size} available, #{rows.count(&:started?)} with guest details"
      end

      def wifi_state
        hotel.hotel_wifi_networks.active.exists? ? state(READY, :success) : state(NEEDS_ATTENTION, :warning)
      end

      def wifi_detail
        count = hotel.hotel_wifi_networks.active.count
        count.positive? ? "#{count} active guest network#{'s' unless count == 1}" : "Add a guest Wi-Fi network."
      end

      def knowledge_documents
        hotel.knowledge_documents
      end

      def state(label, tone)
        State.new(label:, tone:)
      end
    end
  end
end
