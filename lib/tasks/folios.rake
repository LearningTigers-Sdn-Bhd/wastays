# frozen_string_literal: true

namespace :folios do
  desc "Backfill missing folios for operational bookings"
  task backfill_missing: :environment do
    result = Folios::BackfillMissingForOperationalBookings.call

    puts "Created #{result.created.count} folios."
    puts "Skipped #{result.skipped.count} bookings."
    puts "Failed #{result.failed.count} bookings."

    result.failed.each do |item|
      puts "Booking #{item['booking_id']} failed: #{item['reason']}"
    end
  end
end
