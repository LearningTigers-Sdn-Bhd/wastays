# frozen_string_literal: true

module HotelPortal
  module FrontDesk
    # Money figures for a front desk stay card.
    #
    # Mirrors BookingFolio#projected_outstanding_balance, so the card agrees with
    # the balance in the booking workspace header: posted charges and adjustments,
    # plus the nights still to be posted, less what the guest has paid. Payments
    # are stored positive and refunds negative, so `paid` is already net of refunds
    # and `charges - paid == balance` always holds.
    #
    # Everything is summed in Ruby over preloaded associations, so a 25-row page
    # costs no extra queries. Callers must preload
    # `booking_folios: [:folio_transactions, :folio_forecasted_charges]`.
    class StayTotalsPresenter
      # Mirrors BookingFolio#projected_forecasts: a stay that is over or called off
      # has nothing left to post, whatever forecast rows are still lying around.
      SETTLED_STATUSES = %w[cancelled completed no_show voided].freeze

      def initialize(booking)
        @booking = booking
      end

      # Posted charges and adjustments — what the folio has actually billed.
      def posted
        totals[:charge] + totals[:adjustment]
      end

      # Nights forecast but not yet posted by the night audit.
      def upcoming
        @upcoming ||= forecasted_charges.sum { |charge| charge.amount.to_d }
      end

      def charges
        posted + upcoming
      end

      def paid
        totals[:payment]
      end

      def balance
        charges - paid
      end

      private

      def totals
        @totals ||= @booking.booking_folios.flat_map { |folio| folio.folio_transactions.to_a }
                            .each_with_object(Hash.new(0.to_d)) do |transaction, sums|
          sums[transaction.transaction_type.to_sym] += transaction.amount.to_d
        end
      end

      def forecasted_charges
        return [] if @booking.status.in?(SETTLED_STATUSES)

        cutoff = @booking.check_out&.to_date
        return [] if cutoff.blank?

        @booking.booking_folios.reject { |folio| folio.status == "closed" }
                .flat_map { |folio| folio.folio_forecasted_charges.to_a }
                .select { |charge| charge.status == "forecast" && charge.stay_date < cutoff }
      end
    end
  end
end
