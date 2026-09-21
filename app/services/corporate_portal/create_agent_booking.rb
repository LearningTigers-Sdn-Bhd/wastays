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
  # Rooms share one occupancy, which is what keeps per-pax pricing honest: a
  # room's price follows who is in that room, so a party split unevenly is
  # booked as separate searches rather than averaged.
  #
  # The bookings are attributed to the agent three ways: the agency through
  # hotel_corporate_account_id, the person who made it through
  # corporate_booked_by, and the channel through a "travel_agent" source, so
  # they can be told from a booking keyed at the desk in a source-grouped report.
  # No money is taken: they are created unpaid and settle by the relationship --
  # direct bill is invoiced, standard settles at checkout.
  class CreateAgentBooking
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
    end

    def call
      room_type = @hotel.room_types.find_by(id: @params[:room_type_id])
      return failure("Choose a room category.") if room_type.blank?
      return failure("Name the lead guest for each room.") if rooms.empty?

      availability = check_availability(room_type)
      return failure(availability) if availability.is_a?(String)

      create_all(room_type)
    rescue Failed => e
      failure(e.message)
    end

    private

    def rooms_requested = [ @params[:rooms].to_i, rooms.size, 1 ].max

    # CreateManualBooking only checks availability when a room number is given,
    # and an agent sells a category -- so without this the confirm step would
    # accept anything the search had already refused, including a stale page or
    # a second agent taking the last room at the same moment.
    def check_availability(room_type)
      result = AgentStaySearch.call(
        hotel: @hotel, check_in: @params[:check_in], check_out: @params[:check_out],
        adults: @params[:adults], children: @params[:children], rooms: rooms_requested
      )
      return result.error unless result.success?

      option = result.options.find { |candidate| candidate.room_type.id == room_type.id }
      return nil if option&.available?

      "#{room_type.name} no longer has #{ActionController::Base.helpers.pluralize(rooms_requested, 'room')} " \
        "free for these dates."
    end

    # All or nothing. Half a party with rooms and half without is worse than a
    # refusal the agent can act on.
    def create_all(room_type)
      bookings = []

      ActiveRecord::Base.transaction do
        rooms.each_with_index do |guests, index|
          bookings << create_booking(room_type, guests, index)
        end
      end

      Result.new(bookings: bookings, group_booking: group_for(bookings), errors: [])
    end

    def create_booking(room_type, guests, index)
      result = Bookings::CreateManualBooking.new(
        hotel: @hotel, params: booking_params(room_type, guests, index), user: @user
      ).call
      raise Failed, Array(result.errors).to_sentence unless result.success?

      add_companions(result.booking, guests)
      stamp_payment_deadline(result.booking)
      result.booking
    end

    # Standard accounts hold the room against a payment deadline; direct bill is
    # invoiced after the stay and gets no deadline. Stamped here rather than in
    # a model callback so the only bookings carrying one are the ones an agent
    # made, and so the clock starts when the booking was actually taken.
    def stamp_payment_deadline(booking)
      due_at = ::Bookings::PaymentHold.due_at(booking: booking)
      return if due_at.blank?

      booking.update!(payment_due_at: due_at)
    end

    def booking_params(room_type, guests, index)
      lead = guests.first || {}
      {
        guest_name: lead[:name],
        guest_email: lead[:email].presence,
        guest_phone: lead[:phone],
        check_in: @params[:check_in],
        check_out: @params[:check_out],
        adults: [ @params[:adults].to_i, 1 ].max,
        children: @params[:children].to_i,
        room_type_id: room_type.id,
        rate_plan_id: (room_type.corporate_rate_plan || room_type.standard_rate_plan)&.id,
        # The agent sells the category, not a numbered room. The desk assigns one
        # at arrival, as it does for any unassigned reservation.
        require_room_number: false,
        source: "travel_agent",
        hotel_corporate_account_id: @relationship.id,
        # Which agency is already known from the relationship; these say which
        # person there made it, and when. Wall-clock, not the business date --
        # it is a record of an action, not of a hotel trading day.
        corporate_booked_by_id: @user&.id,
        corporate_booked_at: Time.current,
        special_requests: @params[:special_requests].presence,
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
        result = BookingGuests::Add.call(
          booking: booking, actor: @user,
          # Guest requires a country and an agent has only a name; the property's
          # own country stands in until the registration card corrects it.
          attributes: attrs.merge(country: @hotel.country)
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

    # Guest blocks arrive keyed by position, nested under the room they belong
    # to. A room with no named lead is not a room anyone asked for.
    def rooms
      @rooms ||= ordered(@params[:rooms_detail]).filter_map do |room|
        guests = ordered(room.is_a?(Hash) ? room.symbolize_keys[:guests] : nil)
                 .map { |attrs| attrs.to_h.symbolize_keys.slice(:name, :email, :phone) }
                 .reject { |attrs| attrs.values.all?(&:blank?) }
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
