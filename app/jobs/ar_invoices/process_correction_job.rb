# frozen_string_literal: true

module ArInvoices
  class ProcessCorrectionJob < ApplicationJob
    queue_as :default
    class AwaitingValidation < StandardError; end
    retry_on AwaitingValidation, wait: 1.minute, attempts: 30 do |job, error|
      correction = ArInvoiceCorrection.find(job.arguments.first)
      correction.update!(status: "failed", error_message: error.message) if correction.processing?
    end

    def perform(correction_id)
      correction = ArInvoiceCorrection.find(correction_id)
      # Session advisory lock prevents simultaneous provider calls without an open
      # transaction or row locks. Released even if the provider raises.
      ArInvoiceCorrection.connection_pool.with_connection do |connection|
        acquired = connection.select_value("SELECT pg_try_advisory_lock(73491, #{correction.id})")
        raise AwaitingValidation, "Correction is already processing." unless acquired
        begin
          return unless correction.reload.status.in?(%w[processing completed])
          if correction.processing?
            ready = EInvoice::ProcessArCorrection.call!(correction: correction)
            raise AwaitingValidation, "Waiting for LHDN correction validation." unless ready
            correction.update!(status: "completed", error_message: nil)
          end
          Notifications::ArCorrectionDelivery.queue!(correction: correction)
        ensure
          connection.execute("SELECT pg_advisory_unlock(73491, #{correction.id})")
        end
      end
    rescue AwaitingValidation
      raise
    rescue StandardError => e
      correction&.update!(status: "failed", error_message: e.message) if correction&.processing?
      raise
    end
  end
end
