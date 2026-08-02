module NightAudits
  module Evaluation
    module Checks
      class MissingFolios
        REASON = "Booking requires a folio before night audit can close"

        def initialize(context:, serializer: SerializeItems.new)
          @context = context
          @serializer = serializer
        end

        def call
          bookings = @context.financially_relevant_bookings.select do |booking|
            booking.booking_folio.blank? && requires_accounting_folio?(booking)
          end

          { "missing_folio" => @serializer.bookings(bookings, REASON) }
        end

        private

        def requires_accounting_folio?(booking)
          !booking.status.in?(%w[cancelled no_show])
        end
      end
    end
  end
end
