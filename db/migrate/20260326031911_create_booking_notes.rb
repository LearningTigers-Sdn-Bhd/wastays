class CreateBookingNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_notes do |t|
      t.references :booking, null: false, foreign_key: true
      t.text :body, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
