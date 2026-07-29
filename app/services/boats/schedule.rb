# frozen_string_literal: true

module Boats
  # A hotel's boat timetable, and the rules for turning a slot into a timestamp
  # and back. Every surface that offers, stores or reads a boat time goes
  # through here.
  #
  # Staff only ever pick a slot: boat-in lands on the check-in date and boat-out
  # leaves on the check-out date, so the day comes from the stay itself.
  class Schedule
    NONE_LABEL = "No boat transfer"
    TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

    class << self
      # Builds the stored datetime in the property's zone, not the signed-in
      # user's, so a manager in another timezone reads back what they picked.
      def timestamp(hotel:, date:, time:)
        return nil if date.blank? || !valid_time?(time)

        zone = hotel.hotel_time_zone
        hour, minute = time.to_s.split(":").map(&:to_i)
        # Stay dates are stored as timestamps, so read the calendar day in the
        # property's zone too -- otherwise a late arrival read in another zone
        # would land the boat on the wrong day.
        day = date.in_time_zone(zone).to_date
        zone.local(day.year, day.month, day.day, hour, minute)
      end

      def time_of_day(hotel:, timestamp:)
        timestamp&.in_time_zone(hotel.hotel_time_zone)&.strftime("%H:%M")
      end

      def valid_time?(value)
        TIME_FORMAT.match?(value.to_s)
      end

      # Report windows have to open and close on the property's clock. Built from
      # Time.zone instead, a manager in another zone would pull a range shifted
      # by their own offset.
      def day_range(hotel:, from:, to:)
        zone = hotel.hotel_time_zone
        from.in_time_zone(zone).beginning_of_day..to.in_time_zone(zone).end_of_day
      end
    end

    def initialize(hotel)
      @hotel = hotel
    end

    # A hotel with the feature on but no slots configured cannot record a boat
    # time at all, so the input surfaces hide themselves rather than offer an
    # empty control. Read-only surfaces gate on allow_boat_information? alone --
    # stored times stay visible whatever the timetable looks like now.
    def enabled?
      @hotel.allow_boat_information? && (in_times.any? || out_times.any?)
    end

    def in_times
      active_times("boat_in")
    end

    def out_times
      active_times("boat_out")
    end

    def in_choices(current: nil)
      choices("boat_in", current)
    end

    def out_choices(current: nil)
      choices("boat_out", current)
    end

    # Which meals a guest on this boat is entitled to. Archived slots still
    # resolve, so retiring a slot never rewrites the history booked against it.
    def meals_for(timestamp, kind)
      slot_at(self.class.time_of_day(hotel: @hotel, timestamp: timestamp), kind)&.meals || []
    end

    def slot_at(time_of_day, kind)
      return if time_of_day.blank?

      slots.find { |slot| slot.kind == kind.to_s && slot.time_of_day == time_of_day }
    end

    private

    # Archived rows are loaded too: they are how a booking made on a since
    # retired slot still explains itself.
    def slots
      @slots ||= @hotel.hotel_boat_schedules.in_service_order.to_a
    end

    def active_times(kind)
      slots.select { |slot| slot.kind == kind && !slot.archived? }.map(&:time_of_day)
    end

    # A retired slot that a guest is still booked on is offered alongside the
    # live ones, so opening the form never silently rewrites their transfer.
    def choices(kind, current)
      times = active_times(kind)
      times += [ current ] if current.present? && slot_at(current, kind) && times.exclude?(current)

      [ [ NONE_LABEL, "" ] ] + times.sort.map { |time| [ label_for(time), time ] }
    end

    def label_for(time)
      hour, minute = time.split(":").map(&:to_i)
      Time.zone.now.change(hour: hour, min: minute).strftime("%-I:%M %p")
    end
  end
end
