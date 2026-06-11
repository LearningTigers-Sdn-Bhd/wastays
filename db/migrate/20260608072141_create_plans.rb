class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.boolean :most_popular, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :plans, :slug, unique: true
  end
end
