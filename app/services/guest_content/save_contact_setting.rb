# frozen_string_literal: true

module GuestContent
  # Writes the Contact and Escalation page.
  #
  # The row is created on first save, so a hotel that never opened the page
  # has none -- which is what lets the public surfaces stay silent instead of
  # showing an empty desk.
  class SaveContactSetting
    def self.call(...) = new(...).call

    def initialize(hotel, params)
      @hotel = hotel
      @params = params
    end

    def call
      contact.assign_attributes(attributes)
      contact.save
    end

    def contact
      @contact ||= hotel.guest_contact || hotel.build_guest_contact
    end

    private

    attr_reader :hotel, :params

    # Each section of the page saves on its own, so a save carries the fields
    # of one section only. Rewrite a value only when its own section sent it,
    # or a Front desk save would blank the escalation rules.
    def attributes
      attrs = params.to_h.symbolize_keys
      attrs[:escalation_triggers] = normalized_triggers if attrs.key?(:escalation_triggers)
      # A 24-hour desk keeps no clock. Clearing both stops a stale pair of
      # times from coming back if the switch is turned off again later.
      if attrs.key?(:front_desk_open_24h) && ActiveModel::Type::Boolean.new.cast(attrs[:front_desk_open_24h])
        attrs[:front_desk_opens_at] = nil
        attrs[:front_desk_closes_at] = nil
      end
      attrs
    end

    # The checkbox group sends a leading blank and can send anything. Keep only
    # the triggers the model knows.
    def normalized_triggers
      Array(params[:escalation_triggers]).map(&:to_s) & HotelGuestContact::ESCALATION_TRIGGERS
    end
  end
end
