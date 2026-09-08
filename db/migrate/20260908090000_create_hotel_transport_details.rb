# frozen_string_literal: true

# How a guest reaches the property, and where the guest leaves the car.
# One row per hotel, because a hotel has one answer to each of these questions.
#
# The concierge already treats parking, shuttles, and airport transfers as
# facility questions. Before this table the answer only existed as prose, so the
# concierge could say that parking exists but never what it costs.
class CreateHotelTransportDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_transport_details do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }

      # Directions
      t.integer :airport_distance_km
      t.integer :airport_travel_minutes
      t.integer :station_distance_km
      t.integer :station_travel_minutes
      t.integer :city_centre_distance_km
      t.integer :city_centre_travel_minutes
      t.text :directions

      # Transportation
      t.boolean :airport_transfer_offered, null: false, default: false
      t.decimal :airport_transfer_price, precision: 10, scale: 2
      t.integer :airport_transfer_lead_hours
      t.string :shuttle_schedule
      t.string :nearest_transit_stop
      t.string :pickup_point
      t.text :transport_notes

      # Parking
      t.string :parking_availability, null: false, default: "none"
      t.string :parking_type
      t.decimal :parking_price, precision: 10, scale: 2
      t.string :parking_price_unit
      t.integer :parking_spaces
      t.decimal :parking_height_limit_m, precision: 4, scale: 2
      t.boolean :parking_ev_charging, null: false, default: false
      t.boolean :parking_booking_required, null: false, default: false
      t.text :parking_notes

      t.timestamps
    end
  end
end
