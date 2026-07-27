# frozen_string_literal: true

module Folios
  module Charges
    module NightlyChargeCalculation
      extend ActiveSupport::Concern

      private

      def nightly_amount(total_amount, booking, business_date)
        stay_dates = booking_stay_dates(booking)
        nights = stay_dates.length
        return 0.to_d unless nights.positive?

        per_night = (total_amount.to_d / nights).round(2)
        return per_night unless business_date.to_date == stay_dates.last

        total_amount.to_d - (per_night * (nights - 1))
      end

      def booking_stay_dates(booking)
        Bookings::ScheduledStay.stay_dates(
          hotel: booking.hotel,
          check_in: booking.check_in,
          check_out: booking.check_out
        )
      end

      def tax_lines_for(booking)
        tax_lines = Array(booking.tax_lines)
        return tax_lines if tax_lines.any?

        return [] unless booking.tourism_tax_amount.to_d.positive?

        [ { "name" => "Tourism Tax", "amount" => booking.tourism_tax_amount, "type" => "tourism_tax" } ]
      end

      def nightly_room_amount(booking_room, business_date)
        snapshot = nightly_rate_snapshot_for(booking_room, business_date)
        return snapshot["price"].to_d if snapshot.present?

        nightly_amount(booking_room.subtotal, booking_room.booking, business_date)
      end

      def nightly_rate_snapshot_for(booking_room, business_date)
        booking_room.nightly_rate_snapshot.to_h[business_date.to_date.iso8601]
      end

      def tax_postings_for(booking, business_date)
        postings = booking.tax_posting_snapshot.to_h[business_date.to_date.iso8601]
        return postings if postings.present?

        tax_lines_for(booking).each_with_index.map do |tax_line, index|
          tax_line.to_h.merge(
            "amount" => nightly_amount(tax_line_amount(tax_line), booking, business_date).to_s("F"),
            "tax_line_index" => index,
            "source" => tax_line["source"].presence || tax_line[:source].presence || "legacy_tax_lines"
          )
        end
      end

      def tax_line_amount(tax_line)
        (tax_line["amount"].presence || tax_line[:amount]).to_d
      end

      def tax_line_name(tax_line)
        tax_line["name"].presence || tax_line[:name].presence || "Tax"
      end

      def tax_line_identity(tax_line, index)
        identity = tax_line["type"].presence || tax_line[:type].presence || tax_line_name(tax_line).parameterize.presence || "tax"
        "#{identity}:#{index}"
      end
    end
  end
end
