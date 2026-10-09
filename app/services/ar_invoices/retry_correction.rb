# frozen_string_literal: true

module ArInvoices
  class RetryCorrection
    Result = ApplicationResult.define

    def self.call(correction:)
      correction.with_lock do
        return Result.failure("Correction is not awaiting retry.") unless correction.failed?
        uncertain = correction.e_invoice_submissions.where(status: "submitted", uuid: nil).exists?
        return Result.failure("Check MyInvois and link the accepted document UUID before retrying. Acceptance is uncertain.") if uncertain
        original = EInvoiceSubmission.find_by(id: correction.metadata["original_submission_id"])
        correction.e_invoice_submissions.where(status: "invalid").each do |submission|
          history = Array(submission.error_details["attempt_history"])
          history << { uuid: submission.uuid, raw_response: submission.raw_response,
                       document_payload: submission.document_payload, retried_at: Time.current.iso8601 }
          submission.document_payload = EInvoice::ArCorrectionDocumentBuilder.new(
            correction: correction, submission: submission, original_submission: original).build
          submission.update!(status: "pending", uuid: nil, long_id: nil, submission_uid: nil,
            raw_response: {}, error_details: { attempt_history: history })
        end
        return Result.failure("The correction document was canceled in MyInvois. Review it before retrying.") if correction.e_invoice_submissions.where(status: "cancelled").exists?
        correction.update!(status: "processing", error_message: nil)
      end
      Result.success
    end
  end
end
