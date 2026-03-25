class CreateRoomInventories < ActiveRecord::Migration[8.0]
  def change
    create_table :room_inventories do |t|
      t.references :room_type, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :quantity, null: false, default: 0
      t.string :status, null: false, default: 'open'

      t.timestamps
    end
    add_index :room_inventories, [:room_type_id, :date], unique: true
  end
end
