# frozen_string_literal: true

class CreateBookingSources < ActiveRecord::Migration[8.0]
  def up
    create_table :booking_sources do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :kind, null: false, default: "ota"
      t.string :icon
      t.string :badge_color
      t.string :badge_text_color
      t.string :badge_initial, limit: 2
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :booking_sources, :key, unique: true
    add_index :booking_sources, :kind
    add_index :booking_sources, :active

    BookingSource.seed_defaults!
  end

  def down
    drop_table :booking_sources
  end
end
