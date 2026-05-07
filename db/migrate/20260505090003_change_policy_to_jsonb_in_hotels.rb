class ChangePolicyToJsonbInHotels < ActiveRecord::Migration[7.1]
  def up
    execute "UPDATE hotels SET policy = '[]'"

    change_column :hotels, :policy, :jsonb, using: "policy::jsonb", default: [], null: false
  end

  def down
    change_column :hotels, :policy, :text, using: "policy::text"
  end
end
