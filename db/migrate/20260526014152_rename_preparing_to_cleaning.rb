# frozen_string_literal: true

class RenameCleaningToCleaning < ActiveRecord::Migration[8.0]
  def up
    RoomStatus.where(status: "cleaning").update_all(status: "cleaning")
    RoomOperationalAuditLog.where(old_status: "cleaning").update_all(old_status: "cleaning")
    RoomOperationalAuditLog.where(new_status: "cleaning").update_all(new_status: "cleaning")
  end

  def down
    RoomStatus.where(status: "cleaning").update_all(status: "cleaning")
    RoomOperationalAuditLog.where(old_status: "cleaning").update_all(old_status: "cleaning")
    RoomOperationalAuditLog.where(new_status: "cleaning").update_all(new_status: "cleaning")
  end
end
