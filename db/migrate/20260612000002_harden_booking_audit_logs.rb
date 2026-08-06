# frozen_string_literal: true

class HardenBookingAuditLogs < ActiveRecord::Migration[8.0]
  def up
    add_column :booking_audit_logs, :category, :string
    add_column :booking_audit_logs, :source, :string
    add_column :booking_audit_logs, :request_id, :string
    add_column :booking_audit_logs, :occurred_at, :datetime

    execute <<~SQL.squish
      UPDATE booking_audit_logs
      SET source = 'legacy',
          category = 'other',
          occurred_at = created_at
      WHERE source IS NULL OR category IS NULL OR occurred_at IS NULL
    SQL

    change_column_null :booking_audit_logs, :source, false
    change_column_null :booking_audit_logs, :category, false
    change_column_null :booking_audit_logs, :occurred_at, false

    add_index :booking_audit_logs, [ :hotel_id, :occurred_at ], name: "idx_booking_audit_logs_on_hotel_time"
    add_index :booking_audit_logs, [ :auditable_type, :auditable_id, :occurred_at ], name: "idx_booking_audit_logs_on_auditable_time"
    add_index :booking_audit_logs, [ :hotel_id, :category, :occurred_at ], name: "idx_booking_audit_logs_on_hotel_category_time"
    add_index :booking_audit_logs, [ :category, :occurred_at ], name: "idx_booking_audit_logs_on_category_time"
    add_index :booking_audit_logs, :source
    add_index :booking_audit_logs, :request_id
  end

  def down
    remove_index :booking_audit_logs, name: "idx_booking_audit_logs_on_hotel_time"
    remove_index :booking_audit_logs, name: "idx_booking_audit_logs_on_auditable_time"
    remove_index :booking_audit_logs, name: "idx_booking_audit_logs_on_hotel_category_time"
    remove_index :booking_audit_logs, name: "idx_booking_audit_logs_on_category_time"
    remove_index :booking_audit_logs, :source
    remove_index :booking_audit_logs, :request_id

    remove_column :booking_audit_logs, :occurred_at
    remove_column :booking_audit_logs, :request_id
    remove_column :booking_audit_logs, :source
    remove_column :booking_audit_logs, :category
  end
end
