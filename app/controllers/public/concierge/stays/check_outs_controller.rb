module Public
  module Concierge
    module Stays
      # Asks the front desk to check the guest out. The booking comes from the
      # stay session, so there is no lookup stage and no code to type again.
      class CheckOutsController < BaseController
        def new
          @presenter = stay_presenter
        end

        def create
          result = ::Concierge::SubmitCheckOutRequest.new(
            booking: stay_booking,
            guest_notes: params[:guest_notes]
          ).call

          if result.success?
            redirect_to stay_path, notice: "The front desk has your check-out request."
          else
            @presenter = stay_presenter
            @error = result.message
            render :new, status: :unprocessable_content
          end
        end
      end
    end
  end
end
