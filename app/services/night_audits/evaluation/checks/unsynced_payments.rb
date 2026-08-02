module NightAudits
  module Evaluation
    module Checks
      class UnsyncedPayments
        REASON = "Captured payment is not synced to the booking folio"

        def initialize(context:, serializer: SerializeItems.new, folio_state: FolioState.new)
          @context = context
          @serializer = serializer
          @folio_state = folio_state
        end

        def call
          transactions = @context.financially_relevant_bookings.flat_map do |booking|
            next [] unless booking.booking_folio

            booking.payment_transactions.select do |payment_transaction|
              payment_transaction.status == "captured" &&
                !@folio_state.payment_synced?(booking.booking_folio, payment_transaction)
            end
          end

          { "captured_payment_not_synced" => @serializer.payment_transactions(transactions, REASON) }
        end
      end
    end
  end
end
