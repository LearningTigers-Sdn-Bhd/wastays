class AddPreferredChannelManagerToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :preferred_channel_manager, :string
  end
end
