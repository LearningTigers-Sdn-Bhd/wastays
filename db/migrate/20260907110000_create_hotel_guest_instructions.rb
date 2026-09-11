class CreateHotelGuestInstructions < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_guest_instructions do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }
      t.text :arrival_instructions
      t.text :departure_instructions

      t.timestamps
    end
  end
end
