# frozen_string_literal: true

module Concierge
  # What a guest reads on the concierge Property Guide pages and the Wi-Fi
  # page. Staff write all of it in Settings > Guest Content, so the pages and
  # the chatbot give the same answers.
  #
  # The public page passes no booking. The stay page passes the verified stay
  # booking, and only an in-house stay unlocks the Wi-Fi networks.
  class PropertyInfoPresenter
    # House rules first: a guest reads them before the room and payment terms.
    POLICY_KEYS = %w[house_rules room_terms payment_and_deposits].freeze
    # The Property Guide pages, in the order of their tiles. Wi-Fi is a stay
    # service, so it is not one of them.
    GUIDE_SECTIONS = %w[property amenities policies faqs].freeze

    # The heading of each page, and the icon of its tile.
    PAGES = {
      "wifi" => { title: "Wi-Fi", subtitle: "Connect your devices to the property network.", icon: "wifi" },
      "property" => { title: "Property info", subtitle: "Arrival, directions and more about the property.", icon: "info" },
      "amenities" => { title: "Amenities", subtitle: "What the property offers, with hours and prices.", icon: "concierge-bell" },
      "policies" => { title: "Policies", subtitle: "House rules and the terms of your stay.", icon: "shield-check" },
      "faqs" => { title: "FAQs", subtitle: "Answers to common questions.", icon: "message-circle-question-mark" }
    }.freeze

    def initialize(hotel:, booking: nil)
      @hotel = hotel
      @booking = booking
    end

    attr_reader :hotel

    # The stay pages pass the booking, so their links stay inside the stay.
    def stay? = booking.present?

    def wifi_networks
      return [] unless booking&.status.in?(Booking::IN_HOUSE_STATUSES)

      @wifi_networks ||= hotel.hotel_wifi_networks.for_guest.in_display_order.to_a
    end

    def policy = hotel.property_policy
    def instruction = hotel.guest_instruction

    def arrival?
      [ policy&.check_in_time, policy&.check_out_time,
        instruction&.arrival_instructions, instruction&.departure_instructions ].any?(&:present?)
    end

    def amenities
      @amenities ||= HotelPortal::GuestContent::AmenityRow.build(
        hotel: hotel, amenities: Amenity.hotel.where(slug: hotel.amenities).ordered
      )
    end

    def transport
      detail = hotel.transport_detail
      detail if detail && (detail.directions_present? || detail.transportation_present? || detail.parking?)
    end

    def policies
      @policies ||= begin
        documents = text_documents("policy").to_a
        fixed = POLICY_KEYS.filter_map { |key| documents.find { |doc| doc.metadata&.dig("policy_key") == key } }
        fixed + (documents - fixed)
      end
    end

    def policy_guide
      @policy_guide ||= Concierge::PolicyPresenter.new(hotel: hotel, documents: policies, booking: booking)
    end

    FaqGroup = Data.define(:title, :questions)

    # One group for each FAQ document staff wrote, in the order they wrote
    # them. Each question is one pair. A document saved before the pairs
    # existed still has its text, so it becomes one question under its title.
    def faq_groups
      @faq_groups ||= text_documents("faq").map do |document|
        pairs = document.qa_pairs.filter_map do |pair|
          [ pair["question"], pair["answer"] ] if pair["question"].present? && pair["answer"].present?
        end
        FaqGroup.new(title: document.title, questions: pairs.presence || [ [ document.title, document.content ] ])
      end
    end

    def faqs = faq_groups.flat_map(&:questions)

    # A search box earns its place only once the list is long.
    def faq_search? = faqs.size >= 6

    # The one official summary, from Property Settings. It leads the About
    # section; the Additional Information documents follow it.
    def description = hotel.description.presence

    def general_infos
      @general_infos ||= text_documents("general_info").to_a
    end

    # Whether a page has anything to show. A tile with nothing behind it does
    # not show.
    def section?(name)
      case name.to_s
      when "wifi" then wifi_networks.any?
      when "property" then arrival? || transport.present? || description.present? || general_infos.any?
      when "amenities" then amenities.any?
      when "policies" then policy_guide.any?
      when "faqs" then faqs.any?
      else false
      end
    end

    def page(section) = PAGES.fetch(section.to_s)

    # The line under a tile's label. A count tells the guest what is behind it.
    def hint(section)
      case section.to_s
      when "wifi" then "Network and password"
      when "property" then "Arrival and directions"
      when "amenities" then "#{amenities.size} available"
      when "policies" then policy_guide.cards_count == 1 ? "1 policy" : "#{policy_guide.cards_count} policies"
      when "faqs" then faqs.size == 1 ? "1 question" : "#{faqs.size} questions"
      end
    end

    def guide_sections = GUIDE_SECTIONS.select { |section| section?(section) }

    private

    attr_reader :booking

    # A PDF has no text a guest can read here, so only written documents show.
    def text_documents(category)
      hotel.knowledge_documents
        .where(category: category, source_type: "text")
        .where.not(content: [ nil, "" ])
        .order(:created_at)
    end
  end
end
