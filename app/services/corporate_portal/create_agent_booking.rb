# frozen_string_literal: true

module CorporatePortal
  # An agent booking one or more rooms for a guest party, from the corporate
  # portal.
  #
  # One booking is one room -- booking_rooms holds a unique index on booking_id
  # -- so a two-room stay is two bookings joined by a group booking, exactly as
  # Bookings::CreateStaffBooking builds one at the desk. Each goes through
  # Bookings::CreateManualBooking, so every booking gets its booking_room,
  # financial snapshot and folio like any other, with no second creation path to
  # keep in step.
  #
  # Every adult in a room can be named. The first is that room's lead guest and
  # the rest become booking_guests on it -- the same records the desk would add
  # at check-in. They are optional: an agent often holds rooms before knowing
  # who is travelling with whom.
  #
  # A stay is a list of lines (CorporatePortal::StayLine): rooms of one category
  # on one rate for one occupancy. Different categories, rates and parties are
  # different lines of the same stay, all on the same dates, so a room's price
  # still follows exactly who is in that room. A request that names one category
  # at the top level (the older shape) is read as a single line.
  #
  # The bookings are attributed to the agent three ways: the agency through
  # hotel_corporate_account_id, the person who made it through
  # corporate_booked_by, and the channel through a "travel_agent" source, so
  # they can be told from a booking keyed at the desk in a source-grouped report.
  # No money is taken: they are created unpaid and settle by the relationship --
  # direct bill is invoiced, standard settles at checkout.
  class CreateAgentBooking
    include AgentGuestIdentity

    class Failed < StandardError; end

    Result = Struct.new(:bookings, :group_booking, :errors, keyword_init: true) do
      def success? = bookings.present?
      def booking = bookings&.first
    end

    def self.call(...) = new(...).call

    def initialize(relationship:, params:, user: nil)
      @relationship = relationship
      @hotel = relationship.hotel
      @params = params.to_h.symbolize_keys
      @user = user
      @boat_times = AgentBoatTimes.new(hotel: @hotel, params: @params)
    end

    def call
      return failure("Choose a room category.") if lines.empty?

      cart = stay_cart
      early = cart.quotes.filter_map(&:error).reject { |message| message.include?("no longer has") }
      return failure(early) if early.any?
      return failure("Name the lead guest for each room.") if rooms.empty?
      return failure(unnamed_rooms_message) if unnamed_rooms.any?
      return failure(*@boat_times.errors) if @boat_times.errors.any?
      return failure(cart.errors) unless cart.success?

      create_all(cart)
    rescue Failed, Boats::ResolveTimes::InvalidSelection, ActiveRecord::RecordInvalid => e
      failure(e.message)
    end

    private

    # The stay's lines. A request with none, but a category at the top level, is
    # one line of that category: `rooms` rooms for the one occupancy.
    def lines
      @lines ||= begin
        listed = StayLine.parse(@params[:lines])
        listed.presence || StayLine.parse([ @params.slice(:room_type_id, :rate_plan_id, :adults, :children, :child_ages)
                                             .merge(quantity: [ @params[:rooms].to_i, room_blocks.size, 1 ].max) ])
      end
    end

    def stay_cart
      @stay_cart ||= AgentStayCart.call(
        hotel: @hotel, relationship: @relationship, check_in: @params[:check_in], check_out: @params[:check_out], lines: lines
      )
    end

    def rooms_requested = [ lines.sum(&:quantity), 1 ].max

    # The line each room belongs to, in order: every room of the first line, then
    # the second's, and so on. Guest blocks arrive in the same order.
    def room_quotes = @room_quotes ||= stay_cart.quotes.flat_map { |quote| Array.new(quote.rooms, quote) }

    # Positions (1-based) of rooms asked for but left without a lead guest.
    # Booking the named ones alone would hand the agent fewer rooms than they
    # asked for without a word, so the whole request is sent back instead.
    def unnamed_rooms
      @unnamed_rooms ||= (0...rooms_requested).select { |index| room_blocks[index].nil? }.map { |index| index + 1 }
    end

    def unnamed_rooms_message
      "Name the lead guest for #{unnamed_rooms.one? ? 'room' : 'rooms'} #{unnamed_rooms.to_sentence}."
    end

    # All or nothing. Half a party with rooms and half without is worse than a
    # refusal the agent can act on.
    def create_all(cart)
      bookings = []

      ActiveRecord::Base.transaction do
        rooms.each_with_index do |guests, index|
          bookings << create_booking(room_quotes.fetch(index), guests, index)
        end
      end

      Result.new(bookings: bookings, group_booking: group_for(bookings), errors: [])
    end

    def create_booking(quote, guests, index)
      result = Bookings::CreateManualBooking.new(
        hotel: @hotel, params: booking_params(quote, guests, index), user: @user
      ).call
      raise Failed, Array(result.errors).to_sentence unless result.success?

      add_companions(result.booking, guests)
      # Every room in the party takes the same boats, landing on its own stay dates.
      ::Boats::AssignTimes.call(booking: result.booking, params: @boat_times.params)
      stamp_payment_deadline(result.booking)
      result.booking
    end

    # Standard accounts hold the room against a payment schedule -- a deposit
    # within the hotel's hold and the rest before arrival; direct bill is
    # invoiced after the stay and gets none. Written here rather than in a model
    # callback so the only bookings carrying one are the ones an agent made, and
    # so the clock starts when the booking was actually taken. The booking's own
    # deadline is set to the first stage.
    def stamp_payment_deadline(booking)
      ::Bookings::CreatePaymentSchedule.call(booking: booking)
    end

    def booking_params(quote, guests, index)
      lead = guests.first || {}
      line = quote.line
      identity = identity_attributes(country: lead[:country], id_number: lead[:government_id])
      {
        guest_name: lead[:name],
        guest_email: lead[:email].presence,
        guest_phone: lead[:phone],
        # Optional -- an agent often does not know it yet -- but the one lever
        # available before checkout for pricing tourism tax accurately (see
        # Bookings::BuildFinancialSnapshot) instead of assuming a foreign guest.
        guest_country: lead[:country].presence,
        guest_document_type: identity[:document_type],
        guest_government_id: identity[:government_id],
        guest_passport_number: identity[:passport_number],
        # A non-Malaysian Guest record cannot save without one (Guest's own
        # reporting-requirement validation). A Malaysian's does not need typing:
        # setting document_type above is what lets Guest derive it from the IC
        # itself (see #populate_date_of_birth_from_malaysian_ic); this is only
        # the fallback for a passport guest, or an IC that failed to parse.
        guest_date_of_birth: lead[:date_of_birth].presence,
        check_in: @params[:check_in],
        check_out: @params[:check_out],
        # The line's own occupancy, ages included, so each room is priced exactly
        # as the search quoted it.
        adults: line.adults,
        children: line.children,
        child_ages: line.child_ages,
        room_type_id: quote.room_type.id,
        rate_plan_id: quote.rate_plan.id,
        # The agent sells the category, not a numbered room. The desk assigns one
        # at arrival, as it does for any unassigned reservation.
        require_room_number: false,
        # Re-checked at creation too, so no path books a night the property
        # closed -- the search above already refused it, but it is cheap to
        # make the booking itself agree.
        apply_stop_sell_restriction: true,
        apply_arrival_departure_restrictions: true,
        apply_stay_length_restrictions: true,
        source: "travel_agent",
        hotel_corporate_account_id: @relationship.id,
        # Which agency is already known from the relationship; these say which
        # person there made it, and when. Wall-clock, not the business date --
        # it is a record of an action, not of a hotel trading day.
        corporate_booked_by_id: @user&.id,
        corporate_booked_at: Time.current,
        special_requests: @params[:special_requests].presence,
        agent_reference: @params[:agent_reference].to_s.strip.first(100).presence,
        internal_notes: "Booked through the corporate portal by " \
                        "#{@relationship.corporate_account&.name}#{" (room #{index + 1} of #{rooms.size})" if rooms.many?}."
      }.compact
    end

    # Everyone after the lead, named. A block left blank is not a guest, and a
    # companion that will not save is logged rather than failing the booking:
    # the room is held by then, and losing it over a malformed phone number
    # would be worse than a name the desk adds at check-in.
    def add_companions(booking, guests)
      guests.drop(1).select { |attrs| attrs[:name].present? }.each do |attrs|
        # Guest requires a country; the agent's own answer wins when given, and
        # the property's stands in until the registration card corrects it.
        country = attrs[:country].presence || @hotel.country
        result = BookingGuests::Add.call(
          booking: booking, actor: @user,
          attributes: attrs.except(:government_id).merge(
            country: country, **identity_attributes(country: country, id_number: attrs[:government_id])
          )
        )
        next if result.success?

        Rails.logger.warn("Agent booking #{booking.id} could not add #{attrs[:name]}: #{result.errors.to_sentence}")
      end
    end

    def group_for(bookings)
      return nil unless bookings.many?

      result = GroupBookings::CreateFromBookings.call(
        hotel: @hotel, bookings: bookings, actor: @user,
        attributes: {
          name: @relationship.corporate_account&.name.presence || "Agent booking",
          status: "active",
          default_check_in: bookings.first.check_in,
          default_check_out: bookings.first.check_out
        }
      )
      result.success? ? result.group_booking : nil
    rescue StandardError => e
      Rails.logger.warn("Agent booking could not be grouped: #{e.message}")
      nil
    end

    # The rooms that will be booked: every requested room, once each has a lead.
    def rooms
      @rooms ||= room_blocks.compact
    end

    # Guest blocks arrive keyed by position, nested under the room they belong
    # to. A room with no named lead stays in its place as nil, so it can be
    # reported rather than quietly left out.
    def room_blocks
      @room_blocks ||= ordered(@params[:rooms_detail]).map do |room|
        guests = ordered(room.is_a?(Hash) ? room.symbolize_keys[:guests] : nil)
                 .map { |attrs| attrs.to_h.symbolize_keys.slice(:name, :email, :phone, :country, :government_id, :date_of_birth) }
                 .reject { |attrs| attrs.except(:country, :government_id, :date_of_birth).values.all?(&:blank?) }
        guests.presence if guests.first&.dig(:name).present?
      end
    end

    def ordered(collection)
      return collection.sort_by { |index, _| index.to_i }.map(&:last) if collection.is_a?(Hash)

      Array(collection)
    end

    def failure(*messages) = Result.new(bookings: [], errors: messages.flatten.compact_blank)
  end
end
