# frozen_string_literal: true

module CorporatePortal
  # An agent booking a room for a guest, from the corporate portal.
  #
  # It goes through Bookings::CreateManualBooking, the same one-room creation
  # path the front desk and the eZee import use, so the booking gets its
  # booking_room, financial snapshot and folio exactly as any other does -- and
  # inherits that service's availability check, which is what stops an agent
  # selling a room that is already taken.
  #
  # Every adult sharing the room can be named. The first is the lead guest the
  # stay is held under, and the rest become booking_guests on it -- the same
  # records the desk would add at check-in. They are optional: an agent often
  # holds the room before knowing who is travelling with whom.
  #
  # The booking is attributed to the agent through hotel_corporate_account_id.
  # No money is taken here: the booking is created unpaid, and how it settles
  # follows the relationship -- direct bill is invoiced, standard settles at
  # checkout. Collecting payment from the agent at this point is not built yet.
  class CreateAgentBooking
    Result = Struct.new(:booking, :errors, keyword_init: true) do
      def success? = booking.present?
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

      # CreateManualBooking only checks availability when a room number is
      # given, and an agent sells a category rather than a numbered room -- so
      # without this the confirm step would accept anything the search had
      # already refused, including a stale page or a second agent confirming the
      # last room at the same moment.
      availability = AgentStaySearch.call(
        hotel: @hotel, check_in: @params[:check_in], check_out: @params[:check_out],
        adults: @params[:adults], children: @params[:children]
      )
      return failure(availability.error) unless availability.success?

      option = availability.options.find { |candidate| candidate.room_type.id == room_type.id }
      return failure("#{room_type.name} is no longer available for these dates.") unless option&.available?

      result = Bookings::CreateManualBooking.new(
        hotel: @hotel, params: booking_params(room_type), user: @user
      ).call

      return failure(*Array(result.errors)) unless result.success?

      add_companions(result.booking)
      Result.new(booking: result.booking, errors: [])
    end

    private

    # Indexed form fields arrive as a Hash keyed by position, so order is read
    # back from the keys rather than assumed.
    def guests
      @guests ||= begin
        raw = @params[:guests]
        list = raw.is_a?(Hash) ? raw.sort_by { |index, _| index.to_i }.map(&:last) : Array(raw)
        list.map { |attrs| attrs.to_h.symbolize_keys.slice(:name, :email, :phone) }
            .reject { |attrs| attrs.values.all?(&:blank?) }
      end
    end

    def lead_guest = guests.first || {}

    # Everyone after the lead, named. A block left blank is not a guest.
    def companions = guests.drop(1).select { |attrs| attrs[:name].present? }

    def add_companions(booking)
      companions.each do |attrs|
        result = BookingGuests::Add.call(
          booking: booking, actor: @user,
          # Guest requires a country and the export of a name is all an agent
          # has; the property's own country is the sane default, and the desk
          # corrects it on the registration card.
          attributes: attrs.merge(country: @hotel.country)
        )
        next if result.success?

        Rails.logger.warn("Agent booking #{booking.id} could not add #{attrs[:name]}: #{result.errors.to_sentence}")
      end
    end

    def booking_params(room_type)
      {
        guest_name: @params[:guest_name].presence || lead_guest[:name],
        guest_email: (@params[:guest_email].presence || lead_guest[:email]).presence,
        guest_phone: @params[:guest_phone].presence || lead_guest[:phone],
        check_in: @params[:check_in],
        check_out: @params[:check_out],
        adults: [ @params[:adults].to_i, 1 ].max,
        children: @params[:children].to_i,
        room_type_id: room_type.id,
        rate_plan_id: (room_type.corporate_rate_plan || room_type.standard_rate_plan)&.id,
        # The agent sells the category, not a numbered room. The desk assigns
        # one at arrival, as it does for any unassigned reservation.
        require_room_number: false,
        source: "internal",
        hotel_corporate_account_id: @relationship.id,
        special_requests: @params[:special_requests].presence,
        internal_notes: "Booked through the corporate portal by #{@relationship.corporate_account&.name}."
      }.compact
    end

    def failure(*messages) = Result.new(errors: messages.flatten.compact_blank)
  end
end
