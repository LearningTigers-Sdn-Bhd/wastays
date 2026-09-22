module Public
  module Concierge
    module Stays
      # The folio, the invoice, and the other booking PDFs. A guest keeps these
      # through the grace period, which is why the stay page owns them.
      class DocumentsController < BaseController
        def show
          submission = e_invoice_submission if params[:kind] == "e_invoice"
          result = ::Bookings::GuestDocument.new(
            booking: stay_booking,
            kind: params[:kind],
            submission: submission
          ).call

          return redirect_to(stay_path, alert: result.error) unless result.success?

          send_data result.bytes,
            filename: result.filename,
            type: "application/pdf",
            disposition: "attachment"
        end

        private

        def e_invoice_submission
          ::EInvoice::SelectGuestSubmission.new(
            booking: stay_booking,
            submission_id: params[:submission_id]
          ).call
        end
      end
    end
  end
end
