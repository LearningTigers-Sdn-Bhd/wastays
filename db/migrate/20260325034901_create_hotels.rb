class CreateHotels < ActiveRecord::Migration[8.0]
  def change
    create_table :hotels do |t|
      t.string :name
      t.string :address
      t.string :city
      t.string :country
      t.integer :star_rating
      t.references :account, null: false, foreign_key: true
      t.string :status

      t.timestamps
    end
  end
end
