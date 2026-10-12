# frozen_string_literal: true

# What the OTA / channel manager says about a booking, kept apart from
# special_requests so a revision never overwrites what staff wrote.
class AddChannelNotesToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :channel_notes, :text
  end
end
