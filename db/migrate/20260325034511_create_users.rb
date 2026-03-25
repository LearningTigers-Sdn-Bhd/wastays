class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email
      t.string :password_digest
      t.references :account, null: false, foreign_key: true
      t.string :role

      t.timestamps
    end
    add_index :users, :email
  end
end
