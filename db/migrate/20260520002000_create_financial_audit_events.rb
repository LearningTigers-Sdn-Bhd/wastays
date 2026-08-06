# frozen_string_literal: true

class CreateFinancialAuditEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :financial_audit_events do |t|
      t.references :hotel, null: false, foreign_key: true
      t.date :business_date, null: false
      t.string :event_type, null: false
      t.bigint :actor_id
      t.string :actor_type
      t.string :source, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency
      t.references :folio_transaction, foreign_key: true
      t.references :booking_folio, foreign_key: true
      t.references :booking, foreign_key: true
      t.references :payment_transaction, foreign_key: true
      t.references :refund_request, foreign_key: true
      t.references :night_audit, foreign_key: true
      t.references :hotel_business_date, foreign_key: true
      t.string :reason
      t.jsonb :metadata, null: false, default: {}
      t.string :request_id
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :financial_audit_events, [ :hotel_id, :business_date, :occurred_at ], name: "idx_financial_audit_events_on_hotel_date_time"
    add_index :financial_audit_events, [ :hotel_id, :event_type, :occurred_at ], name: "idx_financial_audit_events_on_hotel_event_time"
    add_index :financial_audit_events, :actor_id
    add_index :financial_audit_events, :request_id
    add_index :financial_audit_events, [ :event_type, :folio_transaction_id ], unique: true, where: "folio_transaction_id IS NOT NULL", name: "idx_financial_audit_events_unique_transaction_event"
  end
end
