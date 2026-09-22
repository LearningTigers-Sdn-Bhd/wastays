module Public
  module Concierge
    module Stays
      class EInvoicesController < BaseController
        def show
          @presenter = stay_presenter
          @status = status_payload
        end

        def create
          result = ::EInvoice::RequestForGuest.new(booking: stay_booking).call

          if result.success?
            redirect_to stay_e_invoice_path,
              notice: "We are preparing your e-invoice. You will receive it shortly."
          else
            redirect_to stay_e_invoice_path, alert: result.error
          end
        end

        def status
          render json: status_payload
        end

        private

        def status_payload
          ::EInvoice::GuestStatusPayload.new(
            booking: stay_booking,
            download_url: stay_document_path(:e_invoice)
          ).call
        end
      end
    end
  end
end
