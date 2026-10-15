# frozen_string_literal: true

class AddConfiguredSectionsToHotelTransportDetails < ActiveRecord::Migration[8.0]
  class TransportDetail < ActiveRecord::Base
    self.table_name = "hotel_transport_details"
  end

  def up
    add_column :hotel_transport_details, :configured_sections, :jsonb, default: [], null: false

    TransportDetail.reset_column_information
    TransportDetail.find_each do |detail|
      sections = []
      sections << "directions" if directions_present?(detail)
      sections << "transportation" if transportation_present?(detail)
      sections << "parking" if parking_present?(detail)
      detail.update_columns(configured_sections: sections) if sections.any?
    end
  end

  def down
    remove_column :hotel_transport_details, :configured_sections
  end

  private

  def directions_present?(detail)
    %w[
      airport_distance_km airport_travel_minutes station_distance_km station_travel_minutes
      city_centre_distance_km city_centre_travel_minutes directions
    ].any? { |attribute| detail.public_send(attribute).present? }
  end

  def transportation_present?(detail)
    detail.airport_transfer_offered? || %w[
      airport_transfer_price airport_transfer_lead_hours shuttle_schedule nearest_transit_stop
      pickup_point transport_notes
    ].any? { |attribute| detail.public_send(attribute).present? }
  end

  def parking_present?(detail)
    detail.parking_availability != "none" || detail.parking_ev_charging? ||
      detail.parking_booking_required? || %w[
        parking_type parking_price parking_price_unit parking_spaces
        parking_height_limit_m parking_notes
      ].any? { |attribute| detail.public_send(attribute).present? }
  end
end
