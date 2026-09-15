# frozen_string_literal: true

module HotelPortal
  class OperationalDatesPresenter
    UNAVAILABLE_LABEL = "Unavailable"

    def initialize(hotel:, now: Time.current)
      @hotel = hotel
      @now = now
    end

    def working_date
      return @working_date if defined?(@working_date)

      @working_date = @hotel.current_business_date
    end

    def system_date
      @system_date ||= @now.in_time_zone(@hotel.hotel_time_zone).to_date
    end

    def working_date_value
      working_date&.iso8601
    end

    def working_date_label
      working_date ? format_date(working_date) : UNAVAILABLE_LABEL
    end

    def system_date_value
      system_date.iso8601
    end

    def system_date_label
      format_date(system_date)
    end

    def as_json(*)
      {
        working_date: { value: working_date_value, label: working_date_label },
        system_date: { value: system_date_value, label: system_date_label }
      }
    end

    private

    def format_date(date)
      date.strftime("%d %b %Y")
    end
  end
end
