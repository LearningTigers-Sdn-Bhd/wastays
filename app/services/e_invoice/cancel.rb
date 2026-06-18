# frozen_string_literal: true

module EInvoice
  # Cancels a valid e-invoice submission on MyInvois.
  class Cancel
    def self.call(submission, reason:)
      new(submission, reason: reason).call
    end

    def initialize(submission, reason:)
      @submission = submission
      @reason     = reason.presence || "Cancelled by hotel"
    end

    def call
      return { success: false, error: "Submission is not cancellable." } unless @submission.cancellable?

      client = MyInvois::ClientFactory.build
      client.cancel_document(@submission.uuid, reason: @reason)

      @submission.update!(status: "cancelled", cancelled_at: Time.current)
      { success: true, message: "E-invoice cancelled successfully." }
    rescue MyInvois::Client::ApiError => e
      { success: false, error: e.message }
    end
  end
end
