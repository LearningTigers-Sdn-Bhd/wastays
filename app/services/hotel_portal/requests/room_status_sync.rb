# frozen_string_literal: true

module HotelPortal
  module Requests
    # What a request's status change means for the rooms it covers.
    #
    # Dispatching housekeeping work makes a room dirty; finishing it makes the
    # room ready, but only once nothing else is still owed on that room. A
    # checkout's cleaning says the same of the one room it covers. StatusUpdater
    # said all of it, in four blocks that differed mostly in which words they
    # logged and which id they carried, and each of those blocks said the
    # find-a-room-status-and-set-it part twice.
    class RoomStatusSync
      # Work that still stands between a room and being ready.
      OUTSTANDING_STATUSES = %w[new assigned in_progress].freeze

      RULES = {
        "housekeeping" => {
          id_key: "housekeeping_request_id",
          cleaning_event: "housekeeping_request_dispatched",
          ready_event: "room_status_changed",
          # Dispatching work is what makes the room dirty, and so is starting it.
          cleaning_statuses: %w[new in_progress].freeze,
          # A room state the transition rules refuse is left as it stands.
          force_when_refused: false
        },
        "checkout" => {
          id_key: "checkout_request_id",
          cleaning_event: "checkout_room_cleaning_started",
          ready_event: "checkout_room_cleaning_completed",
          cleaning_statuses: %w[in_progress].freeze,
          # Legacy room states must not stop a checkout from updating the
          # operational status the board shows.
          force_when_refused: true
        }
      }.freeze

      Target = Struct.new(:hotel, :room_type, :room_number, keyword_init: true)

      # A complaint covers no rooms, so there is nothing here for it to do.
      def self.call(request:, kind:, status:)
        rules = RULES[kind.to_s]
        return if rules.nil?

        new(request: request, kind: kind.to_s, status: status.to_s, rules: rules).call
      end

      def initialize(request:, kind:, status:, rules:)
        @request = request
        @kind = kind
        @status = status
        @rules = rules
      end

      def call
        return if room_status.nil?

        targets.each { |target| apply(target) }
      end

      private

      attr_reader :request, :kind, :status, :rules

      def room_status
        return "cleaning" if rules[:cleaning_statuses].include?(status)
        return "ready" if status == "completed"

        nil
      end

      def apply(target)
        return if room_status == "ready" && outstanding_work?(target)

        record = RoomStatus.find_or_create_by!(
          hotel: target.hotel,
          room_type: target.room_type,
          room_number: target.room_number
        )

        result = Rooms::SetStatus.new(
          room_status: record,
          status: room_status,
          user: nil,
          booking: request.booking,
          event_type: room_status == "ready" ? rules[:ready_event] : rules[:cleaning_event],
          reason: reason,
          metadata: { rules[:id_key] => request.id }
        ).call
        return if result.success? || !rules[:force_when_refused]

        record.update!(status: room_status, last_changed_at: Time.current, notes: reason)
      end

      def reason
        @reason ||= if kind == "checkout"
          request.guest_notes.presence || "Checkout requested"
        else
          request.request_details.presence || "Housekeeping completed"
        end
      end

      # -- Which rooms ---------------------------------------------------------

      def targets
        kind == "checkout" ? checkout_targets : housekeeping_targets
      end

      # A housekeeping request covers the room it names, and every room its
      # booking holds besides.
      def housekeeping_targets
        found = []

        if request.room_number.present?
          found << Target.new(
            hotel: request.hotel || request.booking&.hotel,
            room_type: request.room_type || request.booking&.booking_rooms&.first&.room_type,
            room_number: request.room_number
          )
        end

        booking = request.booking
        return found if booking.nil?

        booking_rooms(booking).each do |booking_room|
          next if booking_room.room_number == request.room_number

          found << Target.new(hotel: booking.hotel, room_type: booking_room.room_type, room_number: booking_room.room_number)
        end

        found
      end

      def checkout_targets
        room = checkout_room(request)
        return [] if room.nil?

        [ Target.new(hotel: request.booking.hotel, room_type: room.room_type, room_number: room.room_number) ]
      end

      def booking_rooms(booking)
        booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ])
      end

      # The room a checkout covers: the one its metadata names, or the first its
      # booking holds.
      def checkout_room(record)
        room_number = record.metadata.to_h["room_number"].presence
        rooms = booking_rooms(record.booking)
        rooms = rooms.where(room_number: room_number) if room_number.present?
        rooms.first
      end

      # -- Whether the room is owed anything else ------------------------------

      def outstanding_work?(target)
        kind == "checkout" ? checkout_outstanding?(target) : housekeeping_outstanding?(target)
      end

      # A request reaches its hotel by its own column or through its booking, and
      # names its room the same way, so both have to be asked.
      def housekeeping_outstanding?(target)
        hotel_id = request.hotel_id || request.booking&.hotel_id

        HousekeepingRequest
          .left_joins(booking: :booking_rooms)
          .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: hotel_id)
          .where(
            "housekeeping_requests.room_number = :room_number OR " \
            "(housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
            room_number: target.room_number
          )
          .where(status: OUTSTANDING_STATUSES)
          .where.not(id: request.id)
          .exists?
      end

      def checkout_outstanding?(target)
        housekeeping = HousekeepingRequest
          .where(booking_id: request.booking_id, room_number: target.room_number)
          .where(status: OUTSTANDING_STATUSES)
          .exists?
        return true if housekeeping

        CheckOutRequest
          .where(booking_id: request.booking_id)
          .open_tasks
          .where.not(id: request.id)
          .includes(booking: :booking_rooms)
          .any? { |other| checkout_room(other)&.room_number.to_s == target.room_number.to_s }
      end
    end
  end
end
