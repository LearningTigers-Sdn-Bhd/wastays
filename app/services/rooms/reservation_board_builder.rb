# frozen_string_literal: true

module Rooms
  class ReservationBoardBuilder
    def initialize(hotel:, start_date:, days: 14, filters: {})
      @hotel = hotel
      @start_date = start_date
      @days = days.to_i
      @filters = filters || {}
    end

    def call
      @all_bookings = fetch_all_bookings
      @all_room_statuses = fetch_all_room_statuses
      @all_rates = fetch_all_rates
      @relevant_bookings_by_room = fetch_relevant_bookings_by_room
      groups = room_groups
      {
        dates: dates,
        room_groups: groups,
        status_counts: calculate_status_counts,
        rates: @all_rates
      }
    end

    private

    def fetch_all_rates
      rate_plan_name = @filters[:rate_plan_name]
      return {} if rate_plan_name.blank?

      rates_hash = {}
      scope = RoomRate.joins(:rate_plan, room_type: :hotel)
                      .where(hotels: { id: @hotel.id }, date: dates)
                      .where(rate_plans: { name: rate_plan_name })
                      .select("room_rates.room_type_id, room_rates.date, room_rates.price, room_rates.currency")

      scope.each do |rate|
        rates_hash[[ rate.room_type_id, rate.date ]] = { price: rate.price, currency: rate.currency }
      end
      rates_hash
    end

    def fetch_all_room_statuses
      @hotel.room_statuses.where.not(status: "ready").index_by { |rs| [ rs.room_type_id, rs.room_number.to_s ] }
    end

    def calculate_status_counts
      counts = Hash.new(0)
      @all_bookings.values.flatten.uniq(&:id).each do |booking|
        counts[booking.status] += 1
        counts["all"] += 1
      end
      counts["not_ready"] = @all_room_statuses.size
      counts
    end

    def fetch_all_bookings
      scope = @hotel.bookings
        .includes(booking_notes: :user, booking_rooms: :room_type, booking_guests: :guest)
        .joins(:booking_rooms)
        .where("bookings.check_in::date < ? AND bookings.check_out::date > ?", dates.last + 1.day, @start_date)
        .select("bookings.*, booking_rooms.room_number, booking_rooms.room_type_id")
        .distinct

      scope = apply_filters(scope)
      scope.to_a.group_by { |b| [ b.room_type_id, b.room_number.to_s ] }
    end

    def fetch_relevant_bookings_by_room
      return {} unless dates.include?(Date.current)

      @hotel.bookings
        .joins(:booking_rooms)
        .checking_out_between(Date.current, dates.last, @hotel.hotel_time_zone)
        .where.not(status: "cancelled")
        .order("bookings.check_out ASC")
        .select("bookings.*, booking_rooms.room_number, booking_rooms.room_type_id")
        .to_a
        .group_by { |booking| [ booking.room_type_id, booking.room_number.to_s ] }
        .transform_values(&:first)
    end

    def dates
      @dates ||= (@start_date...(@start_date + @days.days)).to_a
    end

    def room_groups
      @hotel.room_types.order(:name).map do |room_type|
        {
          room_type: room_type,
          rooms: room_type.room_numbers.map { |room_number| room_row(room_type, room_number) }
        }
      end
    end

    def room_row(room_type, room_number)
      blocks = booking_blocks_for(room_type, room_number)

      status = @all_room_statuses[[ room_type.id, room_number.to_s ]]
      if status
        if %w[out_of_service inspection_failed].include?(status.status)
          blocks << {
            id: "rs_#{status.id}",
            type: "room_status",
            status_name: status.status.humanize,
            check_in: @start_date,
            check_out: dates.last + 1.day,
            span: @days,
            start_offset: 0
          }
        elsif dates.include?(Date.current)
          relevant_booking = @relevant_bookings_by_room[[ room_type.id, room_number.to_s ]]
          start_date = relevant_booking ? relevant_booking.check_out.to_date : Date.current

          if dates.include?(start_date) || (start_date < @start_date && (start_date + 1.day) > @start_date)
            display_start = [ start_date, @start_date ].max
            check_out = start_date + 1.day

            # Ensure it doesn't overlap the NEXT future booking
            next_booking = blocks.select { |b| b[:type] == "booking" && b[:check_in] >= start_date }.min_by { |b| b[:check_in] }
            check_out = [ check_out, next_booking[:check_in] ].min if next_booking

            span = (check_out - display_start).to_i

            if span > 0
              blocks << {
                id: "rs_#{status.id}",
                type: "room_status",
                status_name: status.status.humanize,
                check_in: start_date,
                check_out: check_out,
                span: span,
                start_offset: (display_start - @start_date).to_i
              }
            end
          end
        end
      end

      {
        room_type: room_type,
        room_number: room_number,
        blocks: blocks
      }
    end

    def booking_blocks_for(room_type, room_number)
      bookings_for(room_type, room_number).map do |booking|
        booking_room = booking.booking_rooms.find { |br| br.room_type_id == room_type.id && br.room_number.to_s == room_number.to_s }
        {
          id: booking.id,
          type: "booking",
          booking: booking,
          guest_name: booking.guest_name,
          status: booking.status,
          check_in: booking.check_in.to_date,
          check_out: booking.check_out.to_date,
          total_amount: booking.total_amount,
          source: booking.source,
          payment_status: booking.payment_status,
          currency: booking.currency,
          has_notes: booking.booking_notes.any?,
          notes: booking.booking_notes.map { |n| { body: n.body, author: n.user.name, date: n.created_at.strftime("%b %d, %Y %H:%M") } }.to_json,
          room_type_name: room_type.name,
          room_number: room_number,
          booking_room_id: booking_room&.id,
          start_offset: [ (booking.check_in.to_date - @start_date).to_i, 0 ].max,
          span: [ ([ booking.check_out.to_date, dates.last + 1.day ].min - [ booking.check_in.to_date, @start_date ].max).to_i, 1 ].max
        }
      end
    end

    def bookings_for(room_type, room_number)
      @all_bookings[[ room_type.id, room_number.to_s ]] || []
    end

    def apply_filters(scope)
      if @filters[:status].present?
        scope = scope.where(status: @filters[:status])
      else
        # Default statuses for reservation board
        scope = scope.where(status: %w[confirmed review_no_show checked_in pending review_due_out checkout_required no_show])
      end

      # Add more filters here as needed (e.g. source, channel)
      scope
    end
  end
end
