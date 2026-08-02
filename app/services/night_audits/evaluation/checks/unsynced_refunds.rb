module NightAudits
  module Evaluation
    module Checks
      class UnsyncedRefunds
        REASON = "Completed refund is not synced to the booking folio"

        def initialize(context:, serializer: SerializeItems.new, folio_state: FolioState.new)
          @context = context
          @serializer = serializer
          @folio_state = folio_state
        end

        def call
          refunds = @context.financially_relevant_bookings.filter_map do |booking|
            refund_request = booking.refund_request
            next unless booking.booking_folio && refund_request&.completed?

            refund_request unless @folio_state.refund_synced?(booking.booking_folio, refund_request)
          end

          { "refund_not_synced" => @serializer.refund_requests(refunds, REASON) }
        end
      end
    end
  end
end
