# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The Reservation card on the Policies page.
    #
    # Room Revenue owns the charge and the engine bills from it, so the charge is
    # read-only here. The guest note beside it is prose about the same rule, and
    # that is guest content, so it is written here.
    class ReservationPolicyPresenter
      Row = Data.define(:id, :policy_type, :label, :charge, :schedule, :note, :set, :active) do
        def set? = set
        def active? = active
        # Only a policy that posts a charge can carry a note worth reading. An
        # off policy explains nothing, because nothing happens.
        def editable? = set? && active?
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
        @rows ||= LABELS.keys.map { |type| row_for(type) }
      end

      def missing_count = rows.count { |row| !row.set? }

      def complete? = missing_count.zero?

      def notes_count = rows.count { |row| row.note.present? }

      private

      attr_reader :hotel

      def policies
        @policies ||= hotel.hotel_reservation_policies.includes(:transaction_code, :cancellation_tiers).index_by(&:policy_type)
      end

      def row_for(type)
        policy = policies[type]

        Row.new(
          id: policy&.id,
          policy_type: type,
          label: LABELS.fetch(type),
          charge: policy ? policy.pricing_label : "Not set",
          schedule: type == "cancellation" ? cancellation_line : nil,
          note: policy&.description.presence,
          set: policy.present?,
          active: policy&.active? || false
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
