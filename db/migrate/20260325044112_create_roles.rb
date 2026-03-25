class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name
      t.string :slug
      t.references :account, null: true, foreign_key: true

      t.timestamps
    end
    add_index :roles, :slug
    add_index :roles, [:account_id, :slug], unique: true
  end
end
