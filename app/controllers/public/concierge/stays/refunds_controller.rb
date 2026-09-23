module Public
  module Concierge
    module Stays
      # A refund request, not a payment. The record lands as pending and staff
      # decides in the Hotel Portal. No money moves here.
      class RefundsController < BaseController
        def new
          @presenter = stay_presenter
          @refund_request = ::Refunds::Draft.new(booking: stay_booking).call
        end

        def create
          result = ::Refunds::SubmitRequest.new(
            booking: stay_booking,
            params: refund_params,
            mode: :post_stay
          ).call

          if result.success?
            redirect_to stay_path, notice: "We have your refund request. The property will reply to you."
          else
            @presenter = stay_presenter
            @refund_request = RefundRequest.new(refund_params.except(:refund_amount))
            @error = result.error
            render :new, status: :unprocessable_content
          end
        end

        private

        def refund_params = ::Refunds::RequestParams.new(params).call
      end
    end
  end
end
