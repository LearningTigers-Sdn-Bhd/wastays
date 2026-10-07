module NightAudits
  module Evaluation
    module Checks
      class OutstandingFolioBalances
        REASON = "Booking has outstanding folio balance at checkout"

        def initialize(context:, serializer: SerializeItems.new, folio_state: FolioState.new)
          @context = context
          @serializer = serializer
          @folio_state = folio_state
        end

        def call
          bookings = @context.financially_relevant_bookings.select do |booking|
            outstanding_at_checkout?(booking)
          end

          { "outstanding_folio_balance" => @serializer.bookings(bookings, REASON) }
        end

        private

        def outstanding_at_checkout?(booking)
          return false if booking.status == "no_show"

          departure_date = Bookings::ScheduledStay.local_date(hotel: @context.hotel, value: booking.check_out)
          return false unless departure_date == @context.business_date || booking.status == "completed"

          booking.booking_folios.any? do |folio|
            balance = @folio_state.outstanding_balance(folio)
            !balance.zero? && !direct_bill_transferred?(folio, balance)
          end
        end

        def direct_bill_transferred?(folio, balance)
          return false unless folio.closed? && folio.payer_type == "company" && balance.positive?

          receivable = folio.receivable
          receivable.present? && !receivable.void? &&
            receivable.hotel_id == folio.hotel_id &&
            receivable.hotel_corporate_account_id == folio.hotel_corporate_account_id &&
            receivable.currency == folio.currency && receivable.amount.to_d == balance
        end
      end
    end
  end
end
