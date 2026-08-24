# frozen_string_literal: true

module EInvoice
  class RefreshStatusJob < ApplicationJob
    queue_as :default

    MAX_ATTEMPTS = 20
    POLL_INTERVAL = 10.seconds

    retry_on MyInvois::Client::ApiError, wait: :polynomially_longer, attempts: 3

    def perform(submission_id, attempt = 1)
      submission = EInvoiceSubmission.find_by(id: submission_id)
      return unless submission&.refreshable?

      result = EInvoice::RefreshStatus.call(submission)
      return unless result[:success]

      refreshed_submission = result[:submission]
      return unless should_continue_polling?(refreshed_submission, attempt)

      self.class.set(wait: POLL_INTERVAL).perform_later(refreshed_submission.id, attempt + 1)
    end

    private

    def should_continue_polling?(submission, attempt)
      attempt < MAX_ATTEMPTS && submission.refreshable?
    end
  end
end
