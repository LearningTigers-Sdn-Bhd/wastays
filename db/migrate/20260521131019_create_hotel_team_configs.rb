class CreateHotelTeamConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_team_configs do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.text :emails
      t.integer :frequency
      t.string :template_type
      t.datetime :last_alert_sent_at

      t.timestamps
    end
  end
end
