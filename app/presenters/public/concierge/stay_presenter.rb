# frozen_string_literal: true

module Public
  module Concierge
    # The stay facts the page shows, and the actions it offers.
    #
    # The presenter decides what is available. The views only lay it out, so the
    # design session that follows can rebuild the markup without touching a
    # rule.
    class StayPresenter
      def initialize(stay_access:, expires_at: nil, view: nil)
        @stay_access = stay_access
        @expires_at = expires_at
        @view = view
      end

      def booking = @booking ||= stay_access.booking
      def hotel = booking.hotel

      def in_house? = booking.status.in?(Booking::IN_HOUSE_STATUSES)
      def checked_out? = booking.status == "completed"

      def greeting_name
        first = booking.guest_name.to_s.strip.split.first
        first.presence || "Guest"
      end

      def room_label
        booking.room_numbers.presence || "To be assigned"
      end

      def nights
        (booking.check_out.to_date - booking.check_in.to_date).to_i
      end

      def confirmation_code
        booking.confirmation_token.to_s.upcase
      end

      def booking_reference_number
        booking.formatted_reservation_number
      end

      def status_label
        booking.status.humanize
      end

      # ------------------------------------------------------------- availables

      def can_request_check_out?
        in_house? && booking.check_out_requests.open_tasks.none?
      end

      def check_out_pending?
        booking.check_out_requests.open_tasks.any?
      end

      def can_send_request?
        ::Bookings::Occupancy.accepts_guest_requests?(booking)
      end

      def can_toggle_do_not_disturb?
        booking.status == "checked_in" && assigned_rooms.any?
      end

      # Whether housekeeping is being kept away right now.
      #
      # A switch has to show its state, and the state is not on the booking --
      # it is on the room, and it lasts one business date. A guest who turned
      # it on yesterday is not still on it today, which is what active_dnd?
      # settles.
      #
      # Read-only on purpose. Toggling creates the room status row when it is
      # missing; a page that only draws the switch must not write one.
      def do_not_disturb_active?
        return false if assigned_rooms.empty?

        room_statuses.any?(&:active_dnd?)
      end

      def can_request_refund?
        booking.refund_request.blank? || booking.refund_request.rejected?
      end

      def refund_request = booking.refund_request

      def can_request_e_invoice?
        booking.e_invoice_guest_request_possible?
      end

      def e_invoice_ready?
        booking.latest_ready_guest_e_invoice_submission.present?
      end

      def chat_available?
        hotel.concierge_chat_available?
      end

      # A stay page keeps the invoice after check-out, which is the whole point
      # of the grace period.
      def invoice_available?
        checked_out?
      end

      def grace_period_ends_at = @expires_at

      private

      attr_reader :stay_access, :view

      # A room the hotel has actually given the guest. Until then there is
      # nothing for housekeeping to keep away from.
      def assigned_rooms
        @assigned_rooms ||= booking.booking_rooms.where.not(room_number: [ nil, "" ]).to_a
      end

      # One query for the whole booking, then matched in memory: a booking
      # holds a handful of rooms, and a pair of columns cannot be matched as a
      # pair in a WHERE clause without naming every combination of the two.
      def room_statuses
        pairs = assigned_rooms.map { |room| [ room.room_type_id, room.room_number ] }

        RoomStatus.where(hotel_id: booking.hotel_id)
          .where(room_type_id: pairs.map(&:first), room_number: pairs.map(&:last))
          .select { |status| pairs.include?([ status.room_type_id, status.room_number ]) }
      end
    end
  end
end
