# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class OverviewPresenter
      State = Data.define(:label, :tone)

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
          section(:general_info, "Hotel Info", hotel_information_state, hotel_information_detail),
          section(:policy, "Policies", knowledge_state("policy"), knowledge_detail("policy")),
          section(:faq, "FAQs", knowledge_state("faq"), knowledge_detail("faq")),
          section(:amenity, "Amenities", amenities_state, amenities_detail),
          section(:wifi, "Wi-Fi", wifi_state, wifi_detail)
        ]
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

      def section(key, name, status, detail)
        { key: key, name: name, status: status, detail: detail }
      end

      def compute_ai_state
        return state("Needs attention", :warning) unless hotel.ai_concierge_ready?
        return state("Needs attention", :warning) if knowledge_documents.failed.exists?
        return state("Updating", :neutral) if knowledge_documents.where(embedding_status: %w[pending indexing]).exists?

        state("Ready", :success)
      end

      def hotel_information_state
        required = [ hotel.name, hotel.description, hotel.city, hotel.country ]
        required.all?(&:present?) && contact_present? ? state("Ready", :success) : state("Needs attention", :warning)
      end

      def hotel_information_detail
        [ hotel.city, hotel.country ].compact_blank.join(", ").presence || "Add the property location and guest contact details."
      end

      def contact_present?
        [ hotel.contact_email, hotel.contact_phone, hotel.whatsapp_number ].any?(&:present?)
      end

      def knowledge_state(category)
        documents = knowledge_documents.where(category: category)
        return state("Needs attention", :warning) if documents.none? || documents.failed.exists?
        return state("Updating", :neutral) if documents.where(embedding_status: %w[pending indexing]).exists?

        state("Ready", :success)
      end

      def knowledge_detail(category)
        count = knowledge_documents.where(category: category).count
        "#{count} #{category == 'faq' ? 'FAQ collection' : 'policy'}#{'s' unless count == 1}"
      end

      def amenities_state
        hotel.amenities.any? ? state("Ready", :success) : state("Needs attention", :warning)
      end

      def amenities_detail
        selected = hotel.amenities.size
        detailed = hotel.hotel_amenity_details.joins(:amenity).where(amenities: { slug: hotel.amenities }).count
        "#{selected} available, #{detailed} with guest details"
      end

      def wifi_state
        hotel.hotel_wifi_networks.active.exists? ? state("Ready", :success) : state("Needs attention", :warning)
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
