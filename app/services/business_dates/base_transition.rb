# frozen_string_literal: true

module BusinessDates
  class BaseTransition
    MANAGE_PERMISSION = "manage_night_audit".freeze

    def initialize(hotel:, actor: nil, system_context: false)
      @hotel = hotel
      @actor = actor
      @system_context = system_context
    end

    private

    def with_locked_current
      HotelBusinessDate.transaction do
        record = @hotel.hotel_business_dates.current.lock.first
        raise HotelBusinessDate::InvalidTransition, "Hotel has no current accounting business date." unless record

        yield record
      end
    rescue ActiveRecord::RecordNotUnique => e
      raise HotelBusinessDate::InvalidTransition, "Another current accounting business date already exists: #{e.message}"
    end

    def verify_current!(record)
      current = @hotel.hotel_business_dates.current.first
      return if current&.id == record.id

      raise HotelBusinessDate::InvalidTransition, "Business date #{record.business_date} is not the current accounting business date."
    end

    def require_manage_permission!
      return if @system_context
      return if @actor&.superadmin?
      return if @actor&.has_permission?(MANAGE_PERMISSION, hotel: @hotel)

      raise HotelBusinessDate::InvalidTransition, "Actor does not have permission to manage night audit."
    end

    def require_status!(record, expected)
      return if record.status == expected

      raise HotelBusinessDate::InvalidTransition, "Cannot transition business date from #{record.status}; expected #{expected}."
    end
  end
end
