class CreateFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :features do |t|
      t.references :feature_group, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.boolean :leveled, null: false, default: false
      t.boolean :addon, null: false, default: false
      t.timestamps
    end
    add_index :features, :slug, unique: true
  end
end
