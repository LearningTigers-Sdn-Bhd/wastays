class CreateNightAudits < ActiveRecord::Migration[8.0]
  def change
    create_table :night_audits do |t|
      t.references :hotel, null: false, foreign_key: true
      t.date :business_date, null: false
      t.string :status, null: false, default: "pending"
      t.string :trigger_mode, null: false, default: "manual_now"
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :summary, null: false, default: {}
      t.jsonb :exceptions, null: false, default: {}
      t.text :notes
      t.boolean :force_closed, null: false, default: false
      t.references :performed_by_user, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :night_audits, [ :hotel_id, :business_date ], unique: true
    add_index :night_audits, :status
  end
end
