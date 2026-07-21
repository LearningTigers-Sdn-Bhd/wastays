# frozen_string_literal: true

module StayView
  class ResolveCurrentRoomStatus
    Result = Data.define(:physical_status, :operational_flags)

    def self.call(room_status:, operational_date:)
      return Result.new(physical_status: :ready, operational_flags: Immutable.hash(priority: false, dnd: false, late_checkout: false)) unless room_status

      late_checkout = room_status.status == :late_checkout_detected
      Result.new(
        physical_status: late_checkout ? nil : room_status.status,
        operational_flags: Immutable.hash(
          priority: room_status.priority,
          dnd: room_status.dnd && room_status.dnd_date == operational_date,
          late_checkout: late_checkout
        )
      )
    end
  end
end
