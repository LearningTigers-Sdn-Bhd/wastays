# frozen_string_literal: true

module EInvoice
  class SubmitJob < ApplicationJob
    queue_as :default

    retry_on MyInvois::Client::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(submission_id)
      submission = EInvoiceSubmission.find_by(id: submission_id)
      return unless submission

      result = EInvoice::Submit.call(submission)
      return unless result[:success]

      refreshed_submission = result[:submission]
      return unless refreshed_submission&.refreshable?

      EInvoice::RefreshStatusJob.set(wait: 10.seconds).perform_later(refreshed_submission.id)
    end
  end
end
