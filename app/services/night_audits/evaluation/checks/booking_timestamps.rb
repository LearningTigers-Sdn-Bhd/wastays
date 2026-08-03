module NightAudits
  module Evaluation
    module Checks
      class BookingTimestamps
        def initialize(context:, serializer: SerializeItems.new)
          @context = context
          @serializer = serializer
        end

        def call
          {
            "checked_in_missing_timestamp" => @serializer.bookings(
              @context.hotel_bookings.checked_in.where(checked_in_at: nil).includes(:booking_rooms),
              "Checked-in booking is missing check-in timestamp"
            ),
            "completed_missing_timestamp" => @serializer.bookings(
              @context.hotel_bookings.completed.where(checked_out_at: nil).includes(:booking_rooms),
              "Completed booking is missing check-out timestamp"
            )
          }
        end
      end
    end
  end
end
