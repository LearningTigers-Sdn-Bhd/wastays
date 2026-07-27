# frozen_string_literal: true

module Folios
  module Routing
    class GroupRoutingReadiness
      CodeStatus = Data.define(:state, :folio_count)
      BookingStatus = Data.define(:booking, :ready, :reason)

      def initialize(group_booking:)
        @group_booking = group_booking
        @hotel = group_booking.hotel
      end

      def codes
        @codes ||= RoutabilityPolicy.parent_codes(hotel: @hotel).to_a
      end

      def bookings
        @bookings ||= @group_booking.bookings
          .includes(:hotel, :booking_folio, :booking_folios, :booking_billing_parties, :folio_routing_rules, :booking_tax_inclusion_overrides)
          .to_a
      end

      def matrix_for(booking)
        @matrices ||= {}
        @matrices[booking.id] ||= RoutingMatrix.new(booking: booking)
      end

      def code_status(code)
        rows = bookings.filter_map { |booking| matrix_for(booking).rows.find { |row| row.code.id == code.id } }
        return CodeStatus.new(state: :not_routed, folio_count: 0) if rows.all? { |row| row.rule.nil? }

        buckets = rows.filter_map { |row| folio_bucket(row.target_folio) }.uniq
        if buckets.size <= 1
          CodeStatus.new(state: :consistent, folio_count: buckets.size)
        else
          CodeStatus.new(state: :inconsistent, folio_count: buckets.size)
        end
      end

      def booking_status(booking)
        matrix = matrix_for(booking)
        if matrix.parties.none?
          BookingStatus.new(booking: booking, ready: false, reason: "No billing party assigned")
        elsif matrix.folios.none?(&:open?)
          BookingStatus.new(booking: booking, ready: false, reason: "No open folio")
        else
          BookingStatus.new(booking: booking, ready: true, reason: nil)
        end
      end

      private

      # Folios are booking-scoped, so raw folio ids are never comparable across siblings.
      # Bucket by the cross-booking-comparable identity instead: the shared corporate
      # account for company folios, or the payer type for guest folios.
      def folio_bucket(folio)
        return nil unless folio

        folio.hotel_corporate_account_id ? "corp:#{folio.hotel_corporate_account_id}" : "payer:#{folio.payer_type}"
      end
    end
  end
end
