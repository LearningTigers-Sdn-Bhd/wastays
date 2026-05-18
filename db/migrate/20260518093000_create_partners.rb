class CreatePartners < ActiveRecord::Migration[8.0]
  def change
    create_table :partners do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false

      t.timestamps
    end

    add_index :partners, [ :hotel_id, :name ]
    add_index :partners, [ :hotel_id, :code ], unique: true
  end
end
