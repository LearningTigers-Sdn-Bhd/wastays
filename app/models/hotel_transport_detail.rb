# frozen_string_literal: true

# How a guest reaches the property, and where the guest leaves the car.
# One row per hotel. The Getting Around page writes it, and the concierge reads
# it when a guest asks about transfers, public transport, or parking.
#
# The structured columns carry the facts a guest asks for by number: a price, a
# distance, a height limit. The notes columns carry the rest.
class HotelTransportDetail < ApplicationRecord
  # The order here is the order the sheets show them.
  PARKING_AVAILABILITY_OPTIONS = [
    { value: "none", label: "No parking", description: "The property has no parking for guests." },
    { value: "on_site", label: "On-site", description: "Guests park at the property." },
    { value: "nearby", label: "Nearby", description: "Guests park at a car park close to the property." }
  ].freeze

  PARKING_TYPES = [
    { value: "self", label: "Self parking" },
    { value: "valet", label: "Valet" },
    { value: "both", label: "Self parking and valet" }
  ].freeze

  PRICE_UNITS = [
    { value: "free", label: "Free" },
    { value: "hour", label: "Per hour" },
    { value: "night", label: "Per night" },
    { value: "entry", label: "Per entry" }
  ].freeze

  PARKING_AVAILABILITY = PARKING_AVAILABILITY_OPTIONS.map { |option| option[:value] }.freeze
  PARKING_TYPE_VALUES = PARKING_TYPES.map { |option| option[:value] }.freeze
  PRICE_UNIT_VALUES = PRICE_UNITS.map { |option| option[:value] }.freeze

  # Each sheet on the Getting Around page saves one of these groups. The
  # controller permits by section, so a sheet cannot clear a column it never
  # showed.
  SECTION_ATTRIBUTES = {
    "directions" => %i[
      airport_distance_km airport_travel_minutes
      station_distance_km station_travel_minutes
      city_centre_distance_km city_centre_travel_minutes
      directions
    ],
    "transportation" => %i[
      airport_transfer_offered airport_transfer_price airport_transfer_lead_hours
      shuttle_schedule nearest_transit_stop pickup_point transport_notes
    ],
    "parking" => %i[
      parking_availability parking_type parking_price parking_price_unit
      parking_spaces parking_height_limit_m parking_ev_charging
      parking_booking_required parking_notes
    ]
  }.freeze

  SECTIONS = SECTION_ATTRIBUTES.keys.freeze

  DISTANCE_COLUMNS = %i[
    airport_distance_km airport_travel_minutes
    station_distance_km station_travel_minutes
    city_centre_distance_km city_centre_travel_minutes
    airport_transfer_lead_hours parking_spaces
  ].freeze

  belongs_to :hotel

  validates :hotel_id, uniqueness: true
  validates :parking_availability, inclusion: { in: PARKING_AVAILABILITY }
  validates :parking_type, inclusion: { in: PARKING_TYPE_VALUES }, allow_blank: true
  validates :parking_price_unit, inclusion: { in: PRICE_UNIT_VALUES }, allow_blank: true

  validates(*DISTANCE_COLUMNS,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true)
  validates :airport_transfer_price, :parking_price,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :parking_height_limit_m,
    numericality: { greater_than: 0, less_than_or_equal_to: 10 }, allow_nil: true

  def parking?
    parking_availability != "none"
  end

  def parking_free?
    parking_price_unit == "free" || (parking? && parking_price.blank? && parking_price_unit.blank?)
  end

  def directions_present?
    SECTION_ATTRIBUTES.fetch("directions").any? { |column| public_send(column).present? }
  end

  def transportation_present?
    airport_transfer_offered? ||
      SECTION_ATTRIBUTES.fetch("transportation").any? do |column|
        column != :airport_transfer_offered && public_send(column).present?
      end
  end

  def parking_label
    label_for(PARKING_AVAILABILITY_OPTIONS, parking_availability)
  end

  def parking_type_label
    label_for(PARKING_TYPES, parking_type)
  end

  def price_unit_label
    label_for(PRICE_UNITS, parking_price_unit)
  end

  private

  def label_for(options, value)
    options.find { |option| option[:value] == value }&.fetch(:label)
  end
end
