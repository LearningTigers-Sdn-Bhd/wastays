# frozen_string_literal: true

module EInvoice
  class SubmitJob < ApplicationJob
    queue_as :default

    retry_on MyInvois::Client::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(submission_id)
      submission = EInvoiceSubmission.find_by(id: submission_id)
      return unless submission

      EInvoice::Submit.call(submission)
    end
  end
end
