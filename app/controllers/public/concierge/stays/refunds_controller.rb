module Public
  module Concierge
    module Stays
      # A refund request, not a payment. The record lands as pending and staff
      # decides in the Hotel Portal. No money moves here.
      class RefundsController < BaseController
        def new
          @presenter = stay_presenter
          @refund_request = existing_or_new_request
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

        # A rejected request comes back with its details, so the guest does not
        # type the bank information again.
        def existing_or_new_request
          rejected = stay_booking.refund_request
          return RefundRequest.new unless rejected&.rejected?

          RefundRequest.new(
            reason: rejected.reason,
            bank_name: rejected.bank_name,
            account_holder_name: rejected.account_holder_name,
            account_number: rejected.account_number,
            account_type: rejected.account_type
          )
        end

        # A guest whose bank is not listed picks "Other" and types the name in
        # other_bank_name. The name is what the request stores.
        def refund_params
          permitted = params.fetch(:refund_request, {})
            .permit(:reason, :refund_amount, :bank_name, :other_bank_name, :account_holder_name, :account_number, :account_type)
          other_name = permitted.delete(:other_bank_name)
          permitted[:bank_name] = other_name.to_s.strip if permitted[:bank_name] == BankCatalog::OTHER
          permitted
        end
      end
    end
  end
end
