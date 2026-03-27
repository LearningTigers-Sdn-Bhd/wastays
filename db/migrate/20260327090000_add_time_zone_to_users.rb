class AddTimeZoneToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :time_zone, :string, default: "Kuala Lumpur", null: false
  end

  def down
    remove_column :users, :time_zone
  end
end
