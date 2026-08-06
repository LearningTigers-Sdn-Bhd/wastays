class CreateRoomBlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :room_blocks do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :room_type, null: false, foreign_key: true
      t.string :room_number
      t.date :start_date
      t.date :end_date
      t.string :block_type
      t.text :reason
      t.text :notes
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
