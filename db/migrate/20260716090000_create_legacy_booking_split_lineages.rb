# frozen_string_literal: true

class CreateLegacyBookingSplitLineages < ActiveRecord::Migration[8.0]
  def change
    create_table :legacy_booking_split_lineages do |t|
      t.references :legacy_booking, null: false, foreign_key: { to_table: :bookings }
      t.references :group_booking, null: false, foreign_key: true
      t.references :child_booking, null: false, foreign_key: { to_table: :bookings }
      t.references :booking_room, null: false, foreign_key: true
      t.boolean :anchor, null: false, default: false
      t.string :review_status, null: false, default: "approved"
      t.text :review_reason
      t.uuid :batch_id, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :legacy_booking_split_lineages, :batch_id
    add_index :legacy_booking_split_lineages, [ :legacy_booking_id, :batch_id ],
      name: "idx_legacy_split_lineages_booking_batch"
    add_check_constraint :legacy_booking_split_lineages,
      "review_status IN ('pending', 'approved', 'rejected')",
      name: "legacy_split_lineages_review_status_allowed"
  end
end
