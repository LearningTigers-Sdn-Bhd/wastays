class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name
      t.string :slug
      t.string :status

      t.timestamps
    end
    add_index :accounts, :slug
  end
end
