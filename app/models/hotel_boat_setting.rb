# frozen_string_literal: true

# The property's meal service times. These exist only to pre-fill the meal
# entitlements when staff add a schedule slot -- the report always reads the
# stored flags on HotelBoatSchedule, never these.
class HotelBoatSetting < ApplicationRecord
  MEALS = %i[breakfast lunch dinner].freeze

  # Service times are wall-clock labels, not instants -- see HotelBoatSchedule.
  self.time_zone_aware_types = [ :datetime ]

  belongs_to :hotel

  validates :hotel_id, uniqueness: true
  validate :meals_in_service_order

  # Which meals a boat at this time of day would catch, given the property's
  # service times. An arrival catches every meal it lands before; a departure
  # catches every meal it leaves after.
  def meals_for(time_of_day, kind)
    return {} if time_of_day.blank?

    minutes = minutes_since_midnight(time_of_day)
    MEALS.index_with do |meal|
      served = public_send(:"#{meal}_time")
      next false if served.blank?

      kind.to_s == "boat_in" ? minutes <= minutes_since_midnight(served) : minutes >= minutes_since_midnight(served)
    end
  end

  private

  def minutes_since_midnight(value)
    value.hour * 60 + value.min
  end

  def meals_in_service_order
    times = MEALS.filter_map { |meal| public_send(:"#{meal}_time") }
    return if times.size < 2 || times.each_cons(2).all? { |a, b| minutes_since_midnight(a) < minutes_since_midnight(b) }

    errors.add(:base, "Meal times must run breakfast, then lunch, then dinner")
  end
end
