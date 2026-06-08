# frozen_string_literal: true

class RenamePreparingToCleaning < ActiveRecord::Migration[8.0]
  def up
    RoomStatus.where(status: "preparing").update_all(status: "cleaning")
    RoomOperationalAuditLog.where(old_status: "preparing").update_all(old_status: "cleaning")
    RoomOperationalAuditLog.where(new_status: "preparing").update_all(new_status: "cleaning")
  end

  def down
    RoomStatus.where(status: "cleaning").update_all(status: "preparing")
    RoomOperationalAuditLog.where(old_status: "cleaning").update_all(old_status: "preparing")
    RoomOperationalAuditLog.where(new_status: "cleaning").update_all(new_status: "preparing")
  end
end
