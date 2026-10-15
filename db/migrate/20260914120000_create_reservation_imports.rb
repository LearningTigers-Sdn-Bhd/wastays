# frozen_string_literal: true

class CreateReservationImports < ActiveRecord::Migration[8.1]
  def change
    create_table :reservation_imports do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :status, null: false, default: "draft"
      # What the job is doing right now, in words the operator reads.
      t.string :step
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.integer :group_count, null: false, default: 0
      # Per-row failures, so the operator sees which reservations did not land
      # and why without digging through logs.
      t.jsonb :failures, null: false, default: []
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_check_constraint :reservation_imports,
                         "status IN ('draft','queued','running','completed','failed')",
                         name: "reservation_imports_status_allowed"
  end
end
