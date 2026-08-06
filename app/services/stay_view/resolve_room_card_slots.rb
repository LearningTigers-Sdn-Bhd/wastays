# frozen_string_literal: true

module StayView
  class ResolveRoomCardSlots
    OCCUPIED_STATUSES = %i[checked_in due_out_detected checkout_required].freeze
    Result = Data.define(:departure, :current_booking, :current_block, :state)

    def self.call(hotel:, room:, date:, operational_date: date, log_conflicts: true)
      new(
        hotel:,
        room:,
        date: date.to_date,
        operational_date: operational_date.to_date,
        log_conflicts:
      ).call
    end

    def initialize(hotel:, room:, date:, operational_date:, log_conflicts:)
      @hotel = hotel
      @room = room
      @date = date
      @operational_date = operational_date
      @log_conflicts = log_conflicts
    end

    def call
      departures = room.booking_segments.select { |segment| departure?(segment) }
      current_bookings = room.booking_segments.select { |segment| current?(segment) }
      current_blocks = room.operational_segments.select { |segment| active?(segment) }
      warn_on_conflicts(departures:, current_bookings:, current_blocks:)

      departure = departures.min_by { |segment| [ -lifecycle_check_in(segment).jd, segment.booking_id ] }
      current_block = current_blocks.min_by(&:room_block_id)
      current_booking = pick_current_booking(current_bookings) if current_block.nil?

      Result.new(
        departure:,
        current_booking:,
        current_block:,
        state: resolve_state(departure:, current_booking:, current_block:)
      )
    end

    private

    attr_reader :hotel, :room, :date, :operational_date

    def departure?(segment)
      lifecycle_check_out(segment) == date && lifecycle_check_in(segment) < date
    end

    def current?(segment)
      (lifecycle_check_in(segment) <= date && date < lifecycle_check_out(segment)) ||
        (lifecycle_check_in(segment) == date && lifecycle_check_out(segment) == date) ||
        late_occupied?(segment)
    end

    def late_occupied?(segment)
      date == operational_date && OCCUPIED_STATUSES.include?(segment.status) &&
        segment.actual_check_out.nil? && segment.check_in <= date && segment.check_out < date
    end

    def active?(segment)
      segment.start_date <= date && date < segment.end_date
    end

    def pick_current_booking(candidates)
      candidates.min_by do |segment|
        [ lifecycle_check_in(segment) == date ? 0 : 1, -lifecycle_check_in(segment).jd, segment.booking_id ]
      end
    end

    def resolve_state(departure:, current_booking:, current_block:)
      return :blocked if current_block
      return :turnover if departure && current_booking
      return :departure if departure
      return current_booking_state(current_booking) if current_booking

      :vacant
    end

    def current_booking_state(segment)
      return :arrival if lifecycle_check_in(segment) == date
      return :arrival if date == operational_date && !OCCUPIED_STATUSES.include?(segment.status)

      :occupied
    end

    def lifecycle_check_in(segment)
      return segment.check_in if date > operational_date

      segment.actual_check_in || segment.check_in
    end

    def lifecycle_check_out(segment)
      return segment.check_out if date > operational_date

      segment.actual_check_out || segment.check_out
    end

    def warn_on_conflicts(departures:, current_bookings:, current_blocks:)
      return unless @log_conflicts

      conflict = departures.many? || current_bookings.many? || current_blocks.many? ||
        (current_blocks.any? && current_bookings.any?)
      return unless conflict

      payload = {
        event: "stay_view.room_card_slot_conflict",
        hotel_id: hotel.id,
        room_key: room.key,
        date: date.iso8601,
        departure_booking_ids: departures.map(&:booking_id),
        current_booking_ids: current_bookings.map(&:booking_id),
        current_block_ids: current_blocks.map(&:room_block_id)
      }
      Rails.logger.warn(payload.to_json)
    end
  end
end
