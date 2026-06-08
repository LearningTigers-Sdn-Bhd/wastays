# frozen_string_literal: true

class RenamePendingCleaningToDirty < ActiveRecord::Migration[8.0]
  def up
    RoomStatus.where(status: "pending_cleaning").update_all(status: "dirty")
    RoomOperationalAuditLog.where(old_status: "pending_cleaning").update_all(old_status: "dirty")
    RoomOperationalAuditLog.where(new_status: "pending_cleaning").update_all(new_status: "dirty")
  end

  def down
    RoomStatus.where(status: "dirty").update_all(status: "pending_cleaning")
    RoomOperationalAuditLog.where(old_status: "dirty").update_all(old_status: "pending_cleaning")
    RoomOperationalAuditLog.where(new_status: "dirty").update_all(new_status: "pending_cleaning")
  end
end
