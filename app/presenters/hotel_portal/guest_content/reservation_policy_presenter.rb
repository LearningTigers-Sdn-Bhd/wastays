# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The Reservation card on the Policies page.
    #
    # Room Revenue owns these four policies and the engine charges from them.
    # The card only shows what is set, so the page never restates a number that
    # can drift away from the row it came from.
    class ReservationPolicyPresenter
      Row = Data.define(:policy_type, :label, :charge, :note, :set) do
        def set? = set
      end

      LABELS = {
        "cancellation" => "Cancellation",
        "no_show" => "No-show",
        "late_checkout" => "Late checkout",
        "early_departure" => "Early departure"
      }.freeze

      def initialize(hotel)
        @hotel = hotel
      end

      def rows
        @rows ||= HotelReservationPolicy::POLICY_TYPES.sort_by { |type| LABELS.keys.index(type) }.map do |type|
          row_for(type)
        end
      end

      def missing_count = rows.count { |row| !row.set? }

      def complete? = missing_count.zero?

      private

      attr_reader :hotel

      def policies
        @policies ||= hotel.hotel_reservation_policies.includes(:transaction_code, :cancellation_tiers).index_by(&:policy_type)
      end

      def row_for(type)
        policy = policies[type]

        Row.new(
          policy_type: type,
          label: LABELS.fetch(type),
          charge: policy ? policy.pricing_label : "Not set",
          note: type == "cancellation" ? cancellation_line : nil,
          set: policy.present?
        )
      end

      # Cancellation carries a tier table, so one line of prose reads better on a
      # summary card than four rows the hotel already sees in Room Revenue.
      def cancellation_line
        Cancellations::PolicySummary.for_hotel(hotel).to_line
      end
    end
  end
end
