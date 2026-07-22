# frozen_string_literal: true

namespace :hotel_counters do
  # Reconcile hotel document counters to the true max of their backing columns.
  #
  # Bulk-loaded data (DB snapshots, seeds, demo reseeds) can leave a counter
  # behind the real max of the column it feeds, so the next issued number
  # collides with an existing row (e.g. "Folio number has already been taken").
  # This walks every hotel and advances each counter to at least its true max.
  # It only ever moves a counter UP, so it is safe to run repeatedly.
  #
  #   bin/rails hotel_counters:reconcile              # apply
  #   DRY_RUN=1 bin/rails hotel_counters:reconcile    # report only
  desc "Advance hotel document counters to the max of their backing columns"
  task reconcile: :environment do
    dry_run = ENV["DRY_RUN"].present?

    # counter_type => ->(hotel_id) { true max across every column it feeds }
    max_for = {
      "folio" => ->(id) { BookingFolio.where(hotel_id: id).maximum(:folio_number) },
      "invoice" => ->(id) { BookingFolio.where(hotel_id: id).maximum(:invoice_number) },
      "guest_registration" => ->(id) { Booking.where(hotel_id: id).maximum(:guest_registration_number) },
      "reservation" => lambda { |id|
        [ Booking.where(hotel_id: id).maximum(:reservation_number),
          GroupBooking.where(hotel_id: id).maximum(:reservation_number) ].compact.max
      },
      "receipt" => lambda { |id|
        [ Booking.where(hotel_id: id).maximum(:receipt_number),
          GroupBooking.where(hotel_id: id).maximum(:receipt_number) ].compact.max
      }
    }

    adjusted = 0

    Hotel.find_each do |hotel|
      max_for.each do |type, resolver|
        true_max = resolver.call(hotel.id)
        next if true_max.nil?

        counter = HotelCounter.find_or_initialize_by(hotel_id: hotel.id, counter_type: type)
        current = counter.last_value.to_i
        next if current >= true_max

        puts "hotel=#{hotel.id} #{type}: #{current} -> #{true_max}#{dry_run ? ' (dry-run)' : ''}"
        adjusted += 1
        counter.update!(last_value: true_max) unless dry_run
      end
    end

    puts dry_run ? "Would adjust #{adjusted} counter(s)." : "Adjusted #{adjusted} counter(s)."
  end
end
