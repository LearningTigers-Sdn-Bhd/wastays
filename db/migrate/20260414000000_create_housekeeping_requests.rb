class CreateHousekeepingRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :housekeeping_requests do |t|
      t.references :booking, null: false, foreign_key: true
      t.string :external_id
      t.datetime :requested_at, null: false
      t.text :request_details, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :housekeeping_requests, :external_id, unique: true
    add_index :housekeeping_requests, [ :booking_id, :status ]
    add_index :housekeeping_requests, [ :booking_id, :requested_at ]
  end
end
