class AddOwnerPasswordResets < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :auth_version, :integer, default: 0, null: false

    create_table :owner_password_resets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end

    add_index :owner_password_resets, :token_digest, unique: true
  end
end
