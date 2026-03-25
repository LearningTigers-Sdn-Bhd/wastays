class CreateRoomRates < ActiveRecord::Migration[8.0]
  def change
    create_table :room_rates do |t|
      t.references :room_type, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :currency, null: false, default: 'MYR'

      t.timestamps
    end
    add_index :room_rates, [:room_type_id, :date], unique: true
  end
end
