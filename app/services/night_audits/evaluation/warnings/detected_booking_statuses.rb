module NightAudits
  module Evaluation
    module Warnings
      class DetectedBookingStatuses
        def initialize(context:, serializer: SerializeItems.new)
          @context = context
          @serializer = serializer
        end

        def call
          {
            "due_out_detected" => @serializer.bookings(
              detected_bookings("due_out_detected"),
              "Due-out detection carried forward"
            ),
            "no_show_detected" => @serializer.bookings(
              detected_bookings("no_show_detected"),
              "No-show detection carried forward"
            )
          }
        end

        private

        def detected_bookings(status)
          @context.hotel_bookings.where(status: status).includes(:booking_rooms)
        end
      end
    end
  end
end
