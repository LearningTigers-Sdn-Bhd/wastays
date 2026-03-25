class CreateRoomTypes < ActiveRecord::Migration[8.0]
  def change
    create_table :room_types do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name
      t.text :description
      t.integer :max_adults
      t.integer :max_children
      t.integer :quantity
      t.decimal :base_price

      t.timestamps
    end
  end
end
