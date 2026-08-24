class AddGuestChatEnabledToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :guest_chat_enabled, :boolean, default: true, null: false
  end
end
