# frozen_string_literal: true

module Concierge
  # The Policies page for a guest: the facts they ask about most, the rules
  # for changing a stay, and the policy documents staff wrote.
  #
  # The facts come from the settings the property enforces (the times, the
  # reservation charges, the room types), not from the prose, so the page and
  # the bill never disagree.
  #
  # An in-house guest has checked in and can no longer cancel. The stay page
  # passes that booking, and the facts turn to what matters now: when to leave
  # and what a late check-out costs.
  class PolicyPresenter
    Fact = Data.define(:label, :value, :icon)
    Change = Data.define(:label, :charge, :note)

    DOCUMENT_ICONS = {
      "house_rules" => "house",
      "room_terms" => "bed-double",
      "payment_and_deposits" => "credit-card"
    }.freeze
    CHANGE_LABELS = HotelPortal::GuestContent::ReservationPolicyPresenter::LABELS
    PUBLIC_CHANGES = %w[cancellation no_show late_checkout early_departure].freeze
    STAY_CHANGES = %w[late_checkout early_departure].freeze

    def initialize(hotel:, documents:, booking: nil)
      @hotel = hotel
      @documents = documents
      @booking = booking
    end

    attr_reader :documents

    def in_house? = booking&.status.in?(Booking::IN_HOUSE_STATUSES) || false

    def glance
      @glance ||= (in_house? ? stay_glance : public_glance).compact.select { |fact| fact.value.present? }
    end

    def changes_title = in_house? ? "Changes to your stay" : "Changes and cancellation"

    def changes
      @changes ||= (in_house? ? STAY_CHANGES : PUBLIC_CHANGES).filter_map do |type|
        charge = charge_for(type) or next

        Change.new(label: CHANGE_LABELS.fetch(type), charge: charge, note: reservation_policies[type].description.presence)
      end
    end

    def document_icon(document) = DOCUMENT_ICONS.fetch(document.metadata&.dig("policy_key").to_s, "file-text")

    # One card for each document, and one for the changes when there are any.
    def cards_count = documents.size + (changes.any? ? 1 : 0)

    def any? = cards_count.positive?

    private

    attr_reader :hotel, :booking

    def public_glance
      [
        Fact.new(label: "Check-in from", value: policy&.check_in_time, icon: "log-in"),
        Fact.new(label: "Check-out by", value: policy&.check_out_time, icon: "log-out"),
        Fact.new(label: "Cancellation", value: charge_for("cancellation"), icon: "calendar-x"),
        smoking_fact,
        pets_fact
      ]
    end

    def stay_glance
      check_out = [ policy&.check_out_time, I18n.l(booking.check_out.to_date, format: "%a, %-d %b") ].compact.join(" on ")

      [
        Fact.new(label: "Check-out by", value: check_out, icon: "log-out"),
        Fact.new(label: "Late check-out", value: charge_for("late_checkout"), icon: "alarm-clock"),
        smoking_fact,
        pets_fact
      ]
    end

    # What a change costs, or nil when the property does not charge for it.
    def charge_for(type)
      policy = reservation_policies[type]
      return unless policy&.active?

      type == "cancellation" ? (cancellation_line || guest_charge(policy)) : guest_charge(policy)
    end

    def smoking_fact
      return unless room_policies.any?

      Fact.new(label: "Smoking", icon: room_policies.smoking_anywhere? ? "cigarette" : "cigarette-off",
               value: room_policies.smoking_anywhere? ? "Allowed in some rooms" : "Not allowed in rooms")
    end

    def pets_fact
      return unless room_policies.any?

      Fact.new(label: "Pets", icon: "paw-print",
               value: room_policies.pets_anywhere? ? "Allowed in some rooms" : "Not allowed")
    end

    # The portal's label speaks to staff ("Staff enters amount"). A guest
    # needs to know only who sets the amount.
    def guest_charge(policy)
      policy.manual? ? "Ask the front desk" : policy.pricing_label
    end

    def cancellation_line
      @cancellation_line ||= Cancellations::PolicySummary.for_hotel(hotel).to_line
    end

    def policy = hotel.property_policy

    def reservation_policies
      @reservation_policies ||= hotel.hotel_reservation_policies.index_by(&:policy_type)
    end

    def room_policies
      @room_policies ||= HotelPortal::GuestContent::RoomPolicyPresenter.new(hotel)
    end
  end
end
