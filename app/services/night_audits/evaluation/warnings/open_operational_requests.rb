module NightAudits
  module Evaluation
    module Warnings
      class OpenOperationalRequests
        def initialize(context:, serializer: SerializeItems.new)
          @context = context
          @serializer = serializer
        end

        def call
          {
            "open_housekeeping_requests" => @serializer.requests(
              housekeeping_requests,
              :request_details,
              "Housekeeping request still open"
            ),
            "open_complaint_requests" => @serializer.requests(
              complaint_requests,
              :complaint_details,
              "Complaint request still open"
            )
          }
        end

        private

        def housekeeping_requests
          HousekeepingRequest.active
            .joins(:booking)
            .includes(:booking)
            .where(bookings: { hotel_id: @context.hotel.id })
            .where.not(status: %w[completed cancelled])
        end

        def complaint_requests
          ComplaintRequest.active
            .joins(:booking)
            .includes(:booking)
            .where(bookings: { hotel_id: @context.hotel.id })
            .where.not(status: %w[resolved cancelled])
        end
      end
    end
  end
end
