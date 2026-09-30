# frozen_string_literal: true

module CorporatePortal
  # What an agent sees of one room of a stay they booked: what was sold, who is
  # staying, how they arrive, and what each night costs. Identity numbers are
  # masked -- the agent entered them and does not need them echoed back.
  class BookingDetailPresenter
    Guest = Struct.new(:name, :lead, :nationality, :phone, :email, :masked_id, keyword_init: true)
    Night = Struct.new(:date, :amount, keyword_init: true)
    Transfer = Struct.new(:label, :time, :meals, :display, keyword_init: true)

    attr_reader :booking

    delegate :adults, :children, :special_requests, :currency, to: :booking

    def initialize(booking)
      @booking = booking
    end

    def booking_room = @booking_room ||= booking.booking_rooms.first

    def room_type_name
      booking_room&.room_type_snapshot.to_h["name"].presence || booking_room&.room_type&.name || "—"
    end

    def rate_plan_name = booking_room&.rate_plan&.name || "—"

    def room_number = booking_room&.room_number.presence || "Assigned at arrival"

    def nights = (booking.check_out.to_date - booking.check_in.to_date).to_i

    def status_label
      return "In house" if booking.status.in?(Booking::IN_HOUSE_STATUSES)

      {
        "confirmed" => "Confirmed", "completed" => "Checked out", "cancelled" => "Cancelled",
        "no_show_detected" => "No-show", "no_show" => "No-show"
      }.fetch(booking.status, booking.status.to_s.humanize)
    end

    def guests
      booking.booking_guests.sort_by { |guest| [ guest.primary? ? 0 : 1, guest.id ] }.map do |guest|
        Guest.new(
          name: guest.name_snapshot.presence || guest.guest&.name,
          lead: guest.primary?,
          nationality: guest.country_snapshot,
          phone: guest.phone_snapshot,
          email: guest.email_snapshot,
          masked_id: mask(guest.passport_number_snapshot.presence || guest.government_id_snapshot)
        )
      end
    end

    # Boat times are recorded on the lead guest; the meals come off the slot.
    def transfers
      lead = booking.booking_guests.find(&:primary?) || booking.booking_guests.first
      return [] if lead.blank? || !booking.hotel.allow_boat_information?

      [ [ "Boat-in", lead.boat_in_at, "boat_in" ], [ "Boat-out", lead.boat_out_at, "boat_out" ] ].filter_map do |label, time, kind|
        type = lead.public_send("#{kind}_type")
        next if time.blank? && type.blank?

        meals = schedule.meals_for(time, kind, type: type).map { |meal| HotelBoatSetting.meal_label(meal) }
        display = ::Boats::Schedule.display(timestamp: time, type: type, zone: booking.hotel.hotel_time_zone, format: "%d %b, %-I:%M %p")
        Transfer.new(label: label, time: time&.in_time_zone(booking.hotel.hotel_time_zone), meals: meals, display: display)
      end
    end

    # Legs the agent could still fill in: only on a hotel that runs boats and
    # has a timetable to pick from.
    def missing_boat_legs
      return [] unless schedule.enabled?

      lead = booking.booking_guests.find(&:primary?) || booking.booking_guests.first
      { "Boat-in" => lead&.boat_in?, "Boat-out" => lead&.boat_out? }.reject { |_, present| present }.keys
    end

    def nightly_rates
      booking_room&.nightly_rate_snapshot.to_h.sort.map do |date, night|
        Night.new(date: Date.parse(date), amount: night.to_h["price"].to_d)
      end || []
    end

    def editable? = UpdateAgentBookingGuests.editable?(booking)

    private

    def schedule = @schedule ||= ::Boats::Schedule.new(booking.hotel)

    def mask(value)
      value = value.to_s.strip
      return if value.blank?

      "•••• #{value.last(3)}"
    end
  end
end
