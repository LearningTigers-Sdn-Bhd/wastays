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
          bookings = OverdueGuestStays.new(context: @context).due_outs

          { "due_out_not_checked_out" => @serializer.bookings(bookings, REASON) }
        end
      end
    end
  end
end
