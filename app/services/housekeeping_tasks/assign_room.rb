# frozen_string_literal: true

module HousekeepingTasks
  class AssignRoom < RoomOperation
    def initialize(hotel:, room_type_id:, room_number:, date:, assigned_to_id:, current_user:)
      @hotel = hotel
      @room_type_id = room_type_id
      @room_number = room_number
      @date = date
      @assigned_to_id = assigned_to_id.presence
      @current_user = current_user
    end

    def call
      authorize_dispatcher!
      ensure_current_business_date!
      staff = assigned_staff

      RoomStatus.transaction do
        room_status.lock!
        previous = room_status.assigned_to
        return success(room_status: room_status) if previous == staff

        room_status.update!(assigned_to: staff)
        RoomOperationalAuditLog.create!(
          hotel: @hotel,
          room_type: room_status.room_type,
          user: @current_user,
          room_number: room_status.room_number,
          event_type: "housekeeping_room_assignment_changed",
          old_status: room_status.status,
          new_status: room_status.status,
          reason: staff ? "Assigned housekeeping to #{staff.name}" : "Unassigned housekeeping",
          metadata: {
            "previous_assigned_to_id" => previous&.id,
            "previous_assigned_to_name" => previous&.name,
            "assigned_to_id" => staff&.id,
            "assigned_to_name" => staff&.name
          }.compact
        )
      end

      success(room_status: room_status)
    rescue ActiveRecord::RecordNotFound
      raise
    rescue Pundit::NotAuthorizedError
      raise
    rescue StandardError => e
      failure(e.message)
    end

    private

    def assigned_staff
      return if @assigned_to_id.blank?

      HotelPortal::ActiveHousekeepersQuery.new(hotel: @hotel).call.find(@assigned_to_id)
    end
  end
end
