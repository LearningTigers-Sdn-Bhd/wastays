class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.string :token, null: false
      t.string :name
      t.references :bearer, polymorphic: true, index: true
      t.string :status, default: 'active'
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :api_keys, :token, unique: true
  end
end
