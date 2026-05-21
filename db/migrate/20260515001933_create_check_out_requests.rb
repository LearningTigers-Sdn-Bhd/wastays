class CreateCheckOutRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :check_out_requests do |t|
      t.references :booking, null: false, foreign_key: true
      t.string :status, default: "pending", null: false
      t.datetime :requested_at, null: false
      t.datetime :acknowledged_at
      t.references :acknowledged_by_user, null: true, foreign_key: { to_table: :users }
      t.text :guest_notes
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :check_out_requests, [ :booking_id, :status ]
    add_index :check_out_requests, [ :booking_id, :requested_at ]
  end
end
