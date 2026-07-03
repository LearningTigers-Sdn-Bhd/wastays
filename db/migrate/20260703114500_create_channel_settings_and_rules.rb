class CreateChannelSettingsAndRules < ActiveRecord::Migration[8.0]
  def change
    create_table :channel_derived_settings do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :channel_id, null: false
      t.string :pricing_mode, default: "same", null: false # same, multiplier, offset
      t.decimal :pricing_value, precision: 10, scale: 2
      t.string :room_allocation_mode, default: "shared", null: false # shared, custom
      t.integer :room_allocation_value

      t.timestamps
    end

    add_index :channel_derived_settings, [:hotel_id, :channel_id], unique: true

    create_table :channel_availability_rules do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :external_id
      t.string :title
      t.date :start_date, null: false
      t.date :end_date
      t.string :rule_type, null: false # close_out, availability_offset, max_availability
      t.integer :value
      t.string :days # Comma separated list like "mo,tu,we,th,fr,sa,su"
      t.json :affected_channels
      t.json :affected_room_types

      t.timestamps
    end
  end
end
