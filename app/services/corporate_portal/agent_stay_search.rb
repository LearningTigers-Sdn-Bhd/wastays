# frozen_string_literal: true

module CorporatePortal
  # What an agent can sell at one hotel for one set of dates.
  #
  # Availability is counted as capacity -- rooms in the category minus stays
  # that overlap these dates -- rather than read from
  # Bookings::AvailableRoomNumbers.
  #
  # That service answers "which numbered rooms are free", which is the question
  # the front desk asks when assigning one. It plucks room numbers and compacts
  # them, so a reservation with no room assigned yet consumes nothing. The desk
  # can see that and judge; an agent cannot, and would happily sell a fifth room
  # in a four-room category that already holds four unassigned reservations.
  #
  # The public engine's room_inventories would also answer this, but it requires
  # an open row for every night of the stay, so a property that has not
  # published inventory looks empty. Counting real stays works either way.
  #
  # Pricing comes from the corporate audience, so an agent is quoted the
  # corporate plan where the property has one and the standard plan otherwise.
  # Per-agency contracted rates do not exist yet -- every agency currently sees
  # the same corporate rate.
  class AgentStaySearch
    # A stay in one of these states is holding a room over its dates.
    OCCUPYING_STATUSES = %w[confirmed no_show_detected checked_in due_out_detected checkout_required].freeze

    Option = Struct.new(:room_type, :rate_plan, :available_count, :total_amount,
                        :currency, keyword_init: true) do
      def available? = available_count.positive?
    end

    Result = Struct.new(:options, :nights, :error, keyword_init: true) do
      def success? = error.blank?
      def available = options.select(&:available?)
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, check_in:, check_out:, adults: 2, children: 0)
      @hotel = hotel
      # Both callers reach here: the search form sends strings, the confirm step
      # re-checks with whatever it was given.
      @check_in = to_date(check_in)
      @check_out = to_date(check_out)
      @adults = adults.to_i
      @children = children.to_i
    end

    def call
      return failure("Choose an arrival and a departure date.") if @check_in.blank? || @check_out.blank?
      return failure("Departure must be after arrival.") if @check_out <= @check_in
      return failure("Arrival cannot be in the past.") if @check_in < business_date

      Result.new(options: options_for_room_types, nights: (@check_out - @check_in).to_i)
    end

    private

    def to_date(value)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def business_date = @hotel.current_business_date || @hotel.business_date_for

    def options_for_room_types
      @hotel.room_types.includes(:rate_plans).filter_map do |room_type|
        next if room_type.max_adults.to_i.positive? && @adults > room_type.max_adults.to_i

        rate_plan = rate_plan_for(room_type)
        next if rate_plan.blank?

        Option.new(
          room_type: room_type,
          rate_plan: rate_plan,
          available_count: remaining_capacity(room_type),
          total_amount: total_for(room_type, rate_plan),
          currency: @hotel.default_currency.presence || "MYR"
        )
      end
    end

    # The corporate plan when the property has one, the standard plan otherwise.
    def rate_plan_for(room_type)
      room_type.corporate_rate_plan || room_type.standard_rate_plan
    end

    # Rooms the category has, less the stays already holding one over these
    # dates -- assigned or not.
    def remaining_capacity(room_type)
      configured = room_type.rooms.where(archived_at: nil).count
      [ configured - overlapping_stays(room_type), 0 ].max
    end

    def overlapping_stays(room_type)
      @hotel.bookings
            .where(status: OCCUPYING_STATUSES)
            .where("check_in < ? AND check_out > ?", @check_out, @check_in)
            .joins(:booking_rooms)
            .where(booking_rooms: { room_type_id: room_type.id })
            .count
    end

    def total_for(room_type, rate_plan)
      snapshot = Bookings::BuildFinancialSnapshot.new(
        hotel: @hotel, room_type: room_type, rate_plan: rate_plan,
        check_in: @check_in, check_out: @check_out, guest_country: nil,
        adults: @adults, children: @children
      ).call
      snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines)
    rescue ArgumentError
      nil
    end

    def failure(message) = Result.new(options: [], nights: 0, error: message)
  end
end
