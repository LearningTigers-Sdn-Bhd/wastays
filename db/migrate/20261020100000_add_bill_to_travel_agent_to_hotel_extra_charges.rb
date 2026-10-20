# frozen_string_literal: true

# A resort package sold through a travel agent usually covers more than the
# room: the jetty fee and a boat transfer are part of what the agent pays for,
# while the guest still settles their own food and drinks. The flag marks the
# extra charges that bill to the agent on a travel agent booking.
class AddBillToTravelAgentToHotelExtraCharges < ActiveRecord::Migration[8.1]
  def change
    add_column :hotel_extra_charges, :bill_to_travel_agent, :boolean, default: false, null: false
  end
end
