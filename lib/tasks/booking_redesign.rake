# frozen_string_literal: true

namespace :bookings do
  namespace :redesign do
    desc "Report one-room booking migration readiness"
    task readiness: :environment do
      Bookings::RedesignReadiness.call.each { |key, value| puts "#{key}=#{value}" }
    end

    desc "Split every ungrouped legacy multi-room booking into grouped one-room children"
    task split_legacy_multi_room: :environment do
      scope = Booking.joins(:booking_rooms)
        .where(group_booking_id: nil)
        .group("bookings.id")
        .having("COUNT(booking_rooms.id) > 1")

      failures = []
      scope.reorder(:id).pluck(:id).each do |booking_id|
        result = Bookings::SplitLegacyMultiRoom.call(
          booking: Booking.find(booking_id),
          metadata: { source: "bookings:redesign:split_legacy_multi_room" }
        )
        failures << [ booking_id, result.error ] unless result.success?
      end

      if failures.any?
        failures.each { |booking_id, error| warn "booking_id=#{booking_id} error=#{error}" }
        abort "Legacy split failed for #{failures.size} booking(s)."
      end

      remaining = Booking.joins(:booking_rooms).group("bookings.id").having("COUNT(booking_rooms.id) > 1").count.size
      abort "#{remaining} multi-room booking(s) remain." if remaining.positive?

      puts "Legacy multi-room split complete."
    end
  end
end
