# frozen_string_literal: true

module EInvoice
  class ProcessArCorrection
    def self.call!(correction:)
      new(correction: correction).call!
    end

    def initialize(correction:)
      @correction = correction
      @original = EInvoiceSubmission.find_by(id: correction.metadata["original_submission_id"])
    end

    def call!
      return true unless @original
      raise ArgumentError, "Original e-invoice is no longer validated." unless @original.validated?
      return false unless process!("02", @correction.original_receivable.invoice, @correction.credit_reference)
      replacement = @correction.replacement_receivable
      return true unless replacement

      process!("01", replacement.invoice, replacement.formatted_invoice_number)
    end

    private

    def process!(type, invoice, reference)
      submission = @correction.e_invoice_submissions.find_or_initialize_by(document_type: type)
      unless submission.persisted?
        context = SubmissionContext.for_submission(@original)
        submission.assign_attributes(hotel: @correction.hotel, booking: @correction.booking_folio.booking,
          invoice: invoice, document_scenario: "company_invoice_correction", internal_id: reference,
          original_invoice_internal_id: @original.internal_id, status: "pending",
          submission_mode: context.submission_mode, fund_collector: context.fund_collector,
          supplier_name: @original.supplier_name, supplier_tin: @original.supplier_tin,
          represented_taxpayer_tin: context.represented_taxpayer_tin, buyer_snapshot: @original.buyer_snapshot)
        submission.document_payload = ArCorrectionDocumentBuilder.new(
          correction: @correction, submission: submission, original_submission: @original).build
        submission.save!
      end
      return true if submission.validated?
      if submission.uuid.present?
        result = RefreshStatus.call(submission)
        raise ArgumentError, result[:error] unless result[:success]
        raise ArgumentError, "LHDN rejected correction #{reference}. Review its validation errors before retrying." if submission.invalid? || submission.cancelled?
        return submission.validated?
      end
      if submission.submitted?
        raise ArgumentError, "LHDN acceptance for #{reference} is uncertain. Check MyInvois and link its UUID before retrying; it will not be submitted twice."
      end
      raise ArgumentError, "LHDN rejected #{reference}. Review its validation errors before retrying." if submission.invalid?

      context = SubmissionContext.for_submission(submission)
      client = MyInvois::ClientFactory.build(mode: context.submission_mode.to_sym,
        represented_taxpayer_tin: context.represented_taxpayer_tin, setting: context.setting)
      # Record the attempt before the remote side effect. A timeout cannot cause
      # an automatic duplicate submission on retry.
      submission.update!(status: "submitted", submitted_at: Time.current)
      response = client.submit_documents([ submission.document_payload.deep_symbolize_keys ])
      accepted = Array(response["acceptedDocuments"]).first
      if accepted
        submission.update!(uuid: accepted.fetch("uuid"), submission_uid: response["submissionUid"], raw_response: response)
        false
      else
        submission.update!(status: "invalid", raw_response: response, error_details: { response: response })
        raise ArgumentError, "LHDN rejected correction #{reference}. Review the submission errors."
      end
    end
  end
end
