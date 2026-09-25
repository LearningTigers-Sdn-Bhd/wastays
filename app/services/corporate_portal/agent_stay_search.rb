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
  # Pricing comes from the plans the property opened to this agency (RatePlan
  # #ta_access and its agency rules), one option per room category and plan,
  # so an agent can choose between, say, a room-only and a full-board rate.
  class AgentStaySearch
    # A stay in one of these states is holding a room over its dates.
    OCCUPYING_STATUSES = %w[confirmed no_show_detected checked_in due_out_detected checkout_required].freeze

    Option = Struct.new(:room_type, :rate_plan, :available_count, :per_room_amount,
                        :rooms, :currency, :tax_lines, :tourism_tax_note, :restriction, keyword_init: true) do
      # Enough rooms free to satisfy the whole request, not merely one, on
      # dates the property has not closed to this plan.
      def available? = restriction.nil? && available_count >= rooms

      # The property closed these dates to this plan (stop-sell, minimum or
      # maximum stay, no arrivals or departures). Unlike the desk, an agent
      # cannot override any of these, so the option is shown but not sold.
      def restricted? = restriction.present?

      # Each room is priced for the occupancy of a single room, so the booking
      # is that figure once per room. On a per-pax property this is why
      # occupancy is asked per room rather than for the party as a whole.
      def total_amount = per_room_amount && per_room_amount * rooms

      # SST and any other hotel-configured tax, already folded into
      # per_room_amount -- named here so the agent can see what it is made of
      # rather than one unexplained total. Tourism tax is deliberately excluded:
      # it depends on the guest's nationality, which is not known at search
      # time, so it is quoted as a note instead (see tourism_tax_note).
      def tax_total = Array(tax_lines).sum { |line| line["amount"].to_d } * rooms
    end

    # too_small: the categories that cannot hold this party in one room, so the
    # agent is told why they are missing rather than left to guess.
    Result = Struct.new(:options, :nights, :rooms, :error, :too_small, keyword_init: true) do
      def success? = error.blank?
      def available = options.select(&:available?)
      def restricted = options.select(&:restricted?)
    end

    def self.call(...) = new(...).call

    def initialize(hotel:, check_in:, check_out:, adults: 2, children: 0, child_ages: [], rooms: 1, relationship: nil)
      @hotel = hotel
      # Which agency is searching decides which plans it is offered. Without
      # one, only the plans opened to every agency are.
      @relationship = relationship
      # Both callers reach here: the search form sends strings, the confirm step
      # re-checks with whatever it was given.
      @check_in = to_date(check_in)
      @check_out = to_date(check_out)
      @adults = adults.to_i
      @children = children.to_i
      # An age-banded plan prices each child by age; without them every child
      # is priced at the plan's fallback, which is what the agent is quoted.
      @child_ages = Bookings::ChildAges.normalize(child_ages, @children)
      # Rooms are sold with one occupancy between them, so a party split unevenly
      # is booked as separate searches. That keeps per-pax pricing honest: the
      # price of a room follows who is in that room.
      @rooms = [ rooms.to_i, 1 ].max
    end

    def call
      return failure("Choose an arrival and a departure date.") if @check_in.blank? || @check_out.blank?
      return failure("Departure must be after arrival.") if @check_out <= @check_in
      return failure("Arrival cannot be in the past.") if @check_in < business_date

      Result.new(options: options_for_room_types, rooms: @rooms,
                 nights: (@check_out - @check_in).to_i, too_small: too_small)
    end

    private

    def to_date(value)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def business_date = @hotel.current_business_date || @hotel.business_date_for

    def too_small
      @hotel.room_types.reject { |room_type| room_type.fits?(adults: @adults, children: @children) }
    end

    def options_for_room_types
      @hotel.room_types.flat_map do |room_type|
        next [] unless room_type.fits?(adults: @adults, children: @children)

        capacity = nil
        restrictions = restrictions_for(room_type)
        rate_plans_for(room_type).filter_map do |rate_plan|
          option_for(room_type, rate_plan, capacity ||= remaining_capacity(room_type), restrictions)
        end
      end
    end

    # Every restriction the desk may choose to apply, applied without choice:
    # an agent sells what the property has opened, and nothing it has closed.
    def restrictions_for(room_type)
      Bookings::RateOptions.new(
        room_type: room_type, check_in: @check_in, check_out: @check_out,
        apply_stop_sell: true, apply_arrival_departure: true, apply_stay_length: true,
        audience: :corporate
      )
    end

    def option_for(room_type, rate_plan, capacity, restrictions)
      snapshot = snapshot_for(room_type, rate_plan)
      return if snapshot.blank?

      Option.new(
        room_type: room_type,
        rate_plan: rate_plan,
        available_count: capacity,
        per_room_amount: snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines),
        rooms: @rooms,
        currency: @hotel.default_currency.presence || "MYR",
        tax_lines: snapshot.tax_lines.reject { |line| Booking.tourism_tax_line?(line) },
        tourism_tax_note: tourism_tax_note,
        restriction: restrictions.restriction_reason(rate_plan)
      )
    end

    # Guest nationality is not asked at search time, so the tourism tax cannot
    # be quoted as a figure -- only as the same warning the guest-facing quote
    # page gives, so the agent is not surprised by it at checkout.
    def tourism_tax_note
      return nil unless @hotel.tourism_tax_enabled?

      "#{@hotel.default_currency.presence || 'MYR'} " \
        "#{ActiveSupport::NumberHelper.number_to_rounded(@hotel.tourism_tax_amount, precision: 2)} " \
        "tourism tax per room, per night applies to guests with passports from outside Malaysia, " \
        "added at checkout once nationality is known."
    end

    # The category's primary plan first, then the rest by name.
    def rate_plans_for(room_type)
      primary_id = room_type.primary_rate_plan&.id
      offered_plans
        .select { |rate_plan| rate_plan.room_type_rate_plans.any? { |assignment| assignment.room_type_id == room_type.id } }
        .sort_by { |rate_plan| [ rate_plan.id == primary_id ? 0 : 1, rate_plan.name.downcase, rate_plan.id ] }
    end

    # Resolved once per search, not once per room category.
    def offered_plans
      @offered_plans ||= @hotel.rate_plans.offered_to_agency(@relationship)
        .includes(:room_type_rate_plans, :rate_plan_stay_discounts).order(:name, :id).to_a
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

    def snapshot_for(room_type, rate_plan)
      Bookings::BuildFinancialSnapshot.new(
        hotel: @hotel, room_type: room_type, rate_plan: rate_plan,
        check_in: @check_in, check_out: @check_out, guest_country: nil,
        adults: @adults, children: @children, child_ages: @child_ages
      ).call
    rescue ArgumentError
      nil
    end

    def failure(message) = Result.new(options: [], nights: 0, rooms: @rooms, error: message, too_small: [])
  end
end
