class CreateComplaintRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :complaint_requests do |t|
      t.references :booking, null: false, foreign_key: true
      t.string :external_id
      t.datetime :requested_at, null: false
      t.text :complaint_details, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :complaint_requests, :external_id, unique: true
    add_index :complaint_requests, [ :booking_id, :requested_at ]
  end
end
