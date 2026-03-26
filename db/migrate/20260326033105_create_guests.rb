class CreateGuests < ActiveRecord::Migration[8.0]
  def change
    create_table :guests do |t|
      t.string :name
      t.string :email
      t.string :phone
      t.string :government_id
      t.jsonb :metadata

      t.timestamps
    end
  end
end
