class CreateHotelGuestContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_guest_contacts do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }

      t.string :front_desk_phone
      t.string :front_desk_whatsapp
      t.string :front_desk_email
      t.string :front_desk_extension
      t.boolean :front_desk_open_24h, null: false, default: true
      t.time :front_desk_opens_at
      t.time :front_desk_closes_at

      t.string :duty_manager_phone
      t.text :after_hours_message

      t.string :emergency_phone
      t.string :emergency_services_number
      t.text :emergency_instructions

      t.jsonb :escalation_triggers, null: false, default: []
      t.integer :escalation_attempts, null: false, default: 2

      t.timestamps
    end
  end
end
