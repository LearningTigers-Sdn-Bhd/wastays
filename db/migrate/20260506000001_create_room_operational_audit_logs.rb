# frozen_string_literal: true

class CreateRoomOperationalAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :room_operational_audit_logs do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :room_type, foreign_key: true
      t.references :booking, foreign_key: true
      t.references :user, foreign_key: true
      t.string :room_number, null: false
      t.string :event_type, null: false
      t.string :old_status
      t.string :new_status
      t.text :reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :room_operational_audit_logs, [ :hotel_id, :room_number ]
    add_index :room_operational_audit_logs, [ :hotel_id, :event_type ]
    add_index :room_operational_audit_logs, :created_at
  end
end
