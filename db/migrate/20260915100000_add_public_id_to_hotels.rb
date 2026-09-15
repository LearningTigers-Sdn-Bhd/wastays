# frozen_string_literal: true

class AddPublicIdToHotels < ActiveRecord::Migration[8.1]
  def up
    add_column :hotels, :public_id, :uuid
    change_column_default :hotels, :public_id, from: nil, to: -> { "gen_random_uuid()" }

    execute("UPDATE hotels SET public_id = gen_random_uuid() WHERE public_id IS NULL")

    add_index :hotels, :public_id, unique: true
    change_column_null :hotels, :public_id, false
  end

  def down
    remove_column :hotels, :public_id
  end
end
