module NightAudits
  module Evaluation
    module Checks
      class DueOuts
        REASON = "Due out today but still not checked out"

        def initialize(context:, serializer: SerializeItems.new)
          @context = context
          @serializer = serializer
        end

        def call
          cutoff = (@context.business_date + 1.day).in_time_zone(@context.hotel.hotel_time_zone).beginning_of_day
          bookings = @context.hotel_bookings
            .where(status: %w[checked_in checkout_required])
            .where("check_out < ?", cutoff)
            .includes(:booking_rooms)

          { "due_out_not_checked_out" => @serializer.bookings(bookings, REASON) }
        end
      end
    end
  end
end
