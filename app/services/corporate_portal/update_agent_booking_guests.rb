# frozen_string_literal: true

module CorporatePortal
  # A travel agent correcting the guests on a booking they made, before the
  # guests arrive: a misspelt name, a changed phone number, a companion whose
  # details were not known at booking time.
  #
  # Only the details an agent would reasonably hold are editable -- name,
  # contact, nationality, identity number and date of birth -- plus the boat
  # slots, on hotels reached by boat. Everything goes
  # through the same guest services the front desk uses, so the booking's lead
  # fields stay in step and every change lands in the booking's audit trail,
  # attributed to the agent and marked as coming from the portal.
  class UpdateAgentBookingGuests
    include AgentGuestIdentity

    SOURCE = "corporate_portal"
    FIELDS = %i[name phone email country government_id date_of_birth].freeze
    # Columns the edit may write, compared against the stay's snapshot so an
    # untouched guest records nothing.
    WRITABLE = %i[name phone email country date_of_birth document_type government_id passport_number].freeze

    Result = Struct.new(:success?, :errors, keyword_init: true)

    def self.call(...) = new(...).call

    # Before arrival means the stay has not started: still confirmed, and the
    # arrival date not yet behind the property's business date.
    def self.editable?(booking)
      return false unless booking.status == "confirmed"

      business_date = booking.hotel.current_business_date || booking.hotel.business_date_for
      booking.check_in.to_date >= business_date
    end

    def initialize(booking:, user:, guests:, boat: {})
      @booking = booking
      @user = user
      @guests = guests.to_h.transform_keys(&:to_s)
      @boat_times = AgentBoatTimes.new(hotel: booking.hotel, params: boat)
    end

    def call
      return failure("This booking can no longer be changed from the portal.") unless self.class.editable?(@booking)

      errors = []
      ActiveRecord::Base.transaction do
        existing_rows.each { |booking_guest, attrs| errors.concat(update(booking_guest, attrs)) }
        new_rows.each { |attrs| errors.concat(add(attrs)) }
        errors.concat(update_boats) if errors.empty?
        raise ActiveRecord::Rollback if errors.any?
      end

      errors.any? ? failure(*errors) : Result.new(success?: true, errors: [])
    end

    private

    def existing_rows
      @booking.booking_guests.includes(:guest).filter_map do |booking_guest|
        attrs = @guests[booking_guest.id.to_s]
        [ booking_guest, clean(attrs) ] if attrs.present?
      end
    end

    # Blank slots the form offers for companions not named at booking time.
    # Never more people than the room holds adults.
    def new_rows
      room_left = [ @booking.adults.to_i - @booking.booking_guests.size, 0 ].max
      @guests.select { |key, _| key.start_with?("new") }
        .sort_by { |key, _| key.delete_prefix("new").to_i }
        .map { |_, attrs| clean(attrs) }
        .select { |attrs| attrs[:name].present? }
        .first(room_left)
    end

    def clean(attrs)
      attrs.to_h.symbolize_keys.slice(*FIELDS).transform_values { |value| value.to_s.strip }
    end

    def update(booking_guest, attrs)
      return [ "Every guest needs a name." ] if attrs[:name].blank?

      country = attrs[:country].presence || booking_guest.country_snapshot
      changes = attrs.except(:government_id, :country)
        .merge(country: country)
        .merge(identity_attributes(country: country, id_number: attrs[:government_id]))
        .compact_blank
        .merge(email: attrs[:email].presence)
        .slice(*WRITABLE)
      return [] if unchanged?(booking_guest, changes)

      # UpdateSnapshot writes every snapshot column, so what the agent did not
      # touch is carried over from the stay rather than from the guest profile.
      baseline = BookingGuests::UpdateSnapshot::SNAPSHOT_ATTRIBUTES.to_h do |key|
        [ key, booking_guest.public_send(:"#{key}_snapshot") ]
      end.merge(tin: @booking.guest_tin)
      result = BookingGuests::UpdateSnapshot.call(
        booking_guest: booking_guest, attributes: baseline.merge(changes), actor: @user, source: SOURCE
      )
      result.success? ? [] : result.errors.map { |error| "#{attrs[:name]}: #{error}" }
    end

    def add(attrs)
      country = attrs[:country].presence || @booking.hotel.country
      result = BookingGuests::Add.call(
        booking: @booking, actor: @user, source: SOURCE,
        attributes: attrs.except(:government_id).merge(country: country)
          .merge(identity_attributes(country: country, id_number: attrs[:government_id]))
      )
      result.success? ? [] : Array(result.errors).map { |error| "#{attrs[:name]}: #{error}" }
    end

    # Boat times live on the lead guest, like every other booking. Written
    # through UpdateSnapshot so the change is audited as the agent's, and only
    # when a time actually moved.
    def update_boats
      return @boat_times.errors if @boat_times.errors.any?

      attributes = ::Boats::ResolveTimes.call(
        hotel: @booking.hotel, check_in: @booking.check_in, check_out: @booking.check_out, params: @boat_times.params
      )
      lead = @booking.booking_guests.reload.find(&:primary?) || @booking.booking_guests.first
      changed = attributes.reject { |column, value| lead&.public_send(column) == value }
      return [] if lead.blank? || changed.empty?

      baseline = BookingGuests::UpdateSnapshot::SNAPSHOT_ATTRIBUTES.to_h do |key|
        [ key, lead.public_send(:"#{key}_snapshot") ]
      end.merge(tin: @booking.guest_tin)
      result = BookingGuests::UpdateSnapshot.call(
        booking_guest: lead, attributes: baseline, actor: @user, source: SOURCE, bibo_attributes: changed
      )
      result.success? ? [] : result.errors
    end

    def unchanged?(booking_guest, changes)
      changes.all? { |key, value| booking_guest.public_send(:"#{key}_snapshot").to_s == value.to_s }
    end

    def failure(*messages) = Result.new(success?: false, errors: messages.flatten)
  end
end
