class AddBusinessHoursToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :business_starts_at, :time, default: "08:00:00", null: false
    add_column :hotels, :business_ends_at, :time, default: "02:00:00", null: false
    add_column :hotels, :arrival_grace_period, :integer, default: 7200, null: false
  end
end
