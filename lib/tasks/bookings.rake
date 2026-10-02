# frozen_string_literal: true

namespace :bookings do
  desc "Link staff bookings billed to one company to that company's account, so its portal lists them"
  task backfill_corporate_account: :environment do
    linked = 0
    skipped = []

    Booking.where(hotel_corporate_account_id: nil).find_each do |booking|
      account_ids = booking.booking_billing_parties.where(party_kind: "company", archived_at: nil)
        .where.not(hotel_corporate_account_id: nil).distinct.pluck(:hotel_corporate_account_id)
      next if account_ids.empty?

      if account_ids.one?
        booking.update_columns(hotel_corporate_account_id: account_ids.first)
        linked += 1
      else
        skipped << booking.id
      end
    end

    puts "Linked #{linked} bookings."
    puts "Skipped #{skipped.size} bookings with more than one company: #{skipped.join(', ')}" if skipped.any?
  end
end
