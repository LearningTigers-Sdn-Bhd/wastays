# frozen_string_literal: true

module Boats
  # Gives a boat-enabled hotel a working timetable on day one: meal service
  # times plus a generic three-in/three-out day. Staff edit these in Boat
  # Settings -- the point is that the reports and booking screens have something
  # to read before anyone visits that page.
  #
  # Idempotent: existing settings and slots are left exactly as they are.
  class EnsureDefaults
    MEAL_TIMES = { breakfast_time: "08:00", lunch_time: "12:00", dinner_time: "19:00" }.freeze
    SLOT_TIMES = { "boat_in" => %w[09:00 12:00 17:00], "boat_out" => %w[10:00 13:00 18:00] }.freeze

    def self.call(hotel) = new(hotel).call

    def initialize(hotel)
      @hotel = hotel
    end

    def call
      return unless @hotel.allow_boat_information?

      setting = @hotel.hotel_boat_setting || @hotel.create_hotel_boat_setting!(MEAL_TIMES)

      SLOT_TIMES.each do |kind, times|
        times.each { |time| create_slot(setting, kind, time) }
      end
    end

    private

    # Meal entitlements are stored on the slot, so they are resolved once here
    # from the service times rather than read back through the setting later.
    def create_slot(setting, kind, time)
      return if @hotel.hotel_boat_schedules.exists?(kind: kind, time: time)

      slot = @hotel.hotel_boat_schedules.new(kind: kind, time: time)
      setting.meals_for(slot.time, kind).each { |meal, served| slot.public_send(:"has_#{meal}=", served) }
      slot.save!
    end
  end
end
