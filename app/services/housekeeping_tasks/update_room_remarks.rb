# frozen_string_literal: true

module HousekeepingTasks
  class UpdateRoomRemarks < RoomOperation
    def initialize(hotel:, room_type_id:, room_number:, date:, notes:, current_user:)
      @hotel = hotel
      @room_type_id = room_type_id
      @room_number = room_number
      @date = date
      @notes = notes.to_s.strip.presence
      @current_user = current_user
    end

    def call
      authorize_housekeeping!
      ensure_current_business_date!

      RoomStatus.transaction do
        room_status.lock!
        previous_notes = room_status.notes
        return success(room_status: room_status) if previous_notes == @notes

        room_status.update!(notes: @notes)
        RoomOperationalAuditLog.create!(
          hotel: @hotel,
          room_type: room_status.room_type,
          user: @current_user,
          room_number: room_status.room_number,
          event_type: "housekeeping_room_remarks_changed",
          old_status: room_status.status,
          new_status: room_status.status,
          reason: @notes,
          metadata: { "old_notes" => previous_notes, "new_notes" => @notes }.compact
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
  end
end
