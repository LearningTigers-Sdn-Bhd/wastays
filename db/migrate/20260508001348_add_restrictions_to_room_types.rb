class AddRestrictionsToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :room_types, :smoking_allowed, :boolean, default: false, null: false
    add_column :room_types, :pets_allowed, :boolean, default: false, null: false
  end
end
