class CreateFeatureGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_groups do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :feature_groups, :slug, unique: true
  end
end
