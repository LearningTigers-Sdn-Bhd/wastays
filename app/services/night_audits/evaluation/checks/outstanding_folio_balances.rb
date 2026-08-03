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
          return false unless booking.booking_folio
          return false if booking.status == "no_show"

          departure_date = Bookings::ScheduledStay.local_date(hotel: @context.hotel, value: booking.check_out)
          return false unless departure_date == @context.business_date || booking.status == "completed"

          @folio_state.outstanding_balance(booking.booking_folio) != 0.to_d
        end
      end
    end
  end
end
