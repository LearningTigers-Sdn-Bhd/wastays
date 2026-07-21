# frozen_string_literal: true

class AddChannelIdentityToGroupBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :group_bookings, :channel_manager_reference, :string
    add_column :group_bookings, :revision_number, :integer, default: 0, null: false

    add_index :group_bookings, [ :hotel_id, :channel_manager_reference ], unique: true,
      where: "channel_manager_reference IS NOT NULL AND channel_manager_reference <> ''",
      name: "idx_group_bookings_channel_identity"
    add_index :group_bookings, [ :hotel_id, :external_reference ], unique: true,
      where: "external_reference IS NOT NULL AND external_reference <> ''",
      name: "idx_group_bookings_external_identity"
  end
end
