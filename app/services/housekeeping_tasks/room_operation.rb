# frozen_string_literal: true

require "ostruct"

module HousekeepingTasks
  class RoomOperation
    private

    def room_status
      @room_status ||= begin
        room_type = @hotel.room_types.find(@room_type_id)
        normalized_room_number = @room_number.to_s.strip
        raise ActiveRecord::RecordNotFound unless room_type.room_numbers.include?(normalized_room_number)

        @hotel.room_statuses.find_or_create_by!(room_type: room_type, room_number: normalized_room_number)
      end
    end

    def authorize_housekeeping!
      return if dispatcher? || performer?

      raise Pundit::NotAuthorizedError
    end

    def authorize_dispatcher!
      raise Pundit::NotAuthorizedError unless dispatcher?
    end

    def ensure_current_business_date!
      requested_date = Date.parse(@date.to_s)
      current_date = @hotel.current_business_date || @hotel.business_date_for(Time.current)
      return if requested_date == current_date.to_date

      raise ArgumentError, "Housekeeping can only be updated for the current business date."
    rescue Date::Error, TypeError
      raise ArgumentError, "Choose a valid housekeeping date."
    end

    def dispatcher?
      @current_user.has_permission?("dispatch_housekeeping_tasks", hotel: @hotel)
    end

    def performer?
      @current_user.has_permission?("perform_housekeeping_tasks", hotel: @hotel)
    end

    def success(**attributes)
      OpenStruct.new({ success?: true, error: nil }.merge(attributes))
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
