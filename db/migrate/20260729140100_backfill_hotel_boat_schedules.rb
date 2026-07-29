# frozen_string_literal: true

# Seeds hotel_boat_schedules from what is already in use.
#
# Three deliberate choices, each guarding a way this could silently lose data:
#
#   1. Slots come from the union of the configured timetable AND every distinct
#      time already stored on booking_guests. Taking only the timetable would
#      orphan every historical booking made on a slot since removed.
#   2. Meal flags are set from the rules MealPrepReport used before this change,
#      not from any meal-time setting, so no existing count moves.
#   3. Hotels with boat information on but nothing configured get a default
#      timetable. Without it the boat section -- which now hides itself when a
#      hotel has no slots -- would silently vanish for them.
class BackfillHotelBoatSchedules < ActiveRecord::Migration[8.0]
  DEFAULT_BOAT_IN = %w[08:00 11:00 14:00 16:30].freeze
  DEFAULT_BOAT_OUT = %w[07:30 10:00 13:00 15:30].freeze

  def up
    Hotel.find_each do |hotel|
      next unless hotel.allow_boat_information?

      zone = hotel.hotel_time_zone
      %w[boat_in boat_out].each do |kind|
        times = configured_times(hotel, kind) | booked_times(hotel, kind, zone)
        times = defaults_for(kind) if times.empty?

        times.sort.each { |time| create_slot(hotel, kind, time) }
      end
    end
  end

  def down
    HotelBoatSchedule.delete_all
  end

  private

  def configured_times(hotel, kind)
    column = kind == "boat_in" ? hotel.boat_in_times : hotel.boat_out_times
    Array(column).map(&:to_s).select { |time| time.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/) }
  end

  # Distinct time-of-day already stored against this hotel's guests, read in the
  # property's zone so a slot lands on the hour staff actually picked.
  def booked_times(hotel, kind, zone)
    column = "#{kind}_at"
    BookingGuest
      .joins(:booking)
      .where(bookings: { hotel_id: hotel.id })
      .where.not(column => nil)
      .pluck(column)
      .map { |timestamp| timestamp.in_time_zone(zone).strftime("%H:%M") }
      .uniq
  end

  def defaults_for(kind)
    kind == "boat_in" ? DEFAULT_BOAT_IN : DEFAULT_BOAT_OUT
  end

  def create_slot(hotel, kind, time)
    meals = legacy_meals(time, kind)
    HotelBoatSchedule.create!(
      hotel_id: hotel.id,
      kind: kind,
      time: time,
      has_breakfast: meals.include?("Breakfast"),
      has_lunch: meals.include?("Lunch"),
      has_dinner: meals.include?("Dinner")
    )
  end

  # The pre-change rules, reproduced verbatim so the switch is a no-op on every
  # existing Meal Prep number.
  def legacy_meals(time, kind)
    hour = time.split(":").first.to_i
    period = if hour < 12 then 1 elsif hour < 17 then 2 else 3 end
    meals = %w[Breakfast Lunch Dinner]

    kind == "boat_in" ? meals.last(meals.size - period + 1) : meals.first(period)
  end
end
