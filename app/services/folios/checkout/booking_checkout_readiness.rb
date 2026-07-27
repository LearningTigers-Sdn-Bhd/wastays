# frozen_string_literal: true


module Folios
  module Checkout
    class BookingCheckoutReadiness
      # Whether a booking can check out, and what stands in the way. Reporting no
      # blockers is the same statement as being ready, so both travel together.
      Report = Data.define(:"ready?", :blockers, :folios, :projected_balance)

      def self.call(booking:, hotel: nil)
        new(booking: booking, hotel: hotel).call
      end

      def initialize(booking:, hotel: nil)
        @booking = booking
        @hotel = hotel || booking.hotel
      end

      def call
        folios = @booking.booking_folios.includes(:folio_forecasted_charges, :folio_transactions).to_a
        blockers = []
        blockers << "Booking has no folio." if folios.empty?

        folios.each do |folio|
          label = folio.display_name
          blockers << "#{label} is #{folio.status}." unless folio.open?

          projected = folio.projected_outstanding_balance.to_d
          unless projected.zero?
            balance_label = if projected.positive?
              "Guest owes #{folio.currency} #{format('%.2f', projected)}"
            else
              "Hotel owes guest #{folio.currency} #{format('%.2f', projected.abs)}"
            end
            balance_label = "#{label}: #{balance_label}" if folios.size > 1
            blockers << balance_label
          end

          pending = folio.projected_forecasts.count
          if pending.positive?
            pending_label = "#{pending} upcoming #{'charge'.pluralize(pending)} pending"
            pending_label = "#{label}: #{pending_label}" if folios.size > 1
            blockers << pending_label
          end
        end

        business_date_record = @hotel.current_business_date_record
        blockers << "Audit is running." if business_date_record&.audit_running?
        blockers << "Audit is blocked." if business_date_record&.audit_blocked?

        Report.new(
          "ready?": blockers.empty?,
          blockers: blockers,
          folios: folios,
          projected_balance: folios.sum { |folio| folio.projected_outstanding_balance.to_d }
        )
      end
    end
  end
end
