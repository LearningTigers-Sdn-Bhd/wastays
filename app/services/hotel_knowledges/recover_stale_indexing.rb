# frozen_string_literal: true

module HotelKnowledges
  class RecoverStaleIndexing
    STALE_AFTER = 30.minutes
    MAX_RECOVERY_ATTEMPTS = 1
    TIMEOUT_ERROR = "Indexing timed out after one automatic retry. Reindex the document to try again."

    Result = Data.define(:retried, :failed)

    def initialize(now: Time.current)
      @now = now
    end

    def call
      retried = 0
      failed = 0

      candidates.find_each do |document|
        action = recover(document)
        retried += 1 if action == :retry
        failed += 1 if action == :failed
      end

      Result.new(retried:, failed:)
    end

    private

    attr_reader :now

    def candidates
      HotelKnowledgeDocument
        .joins(:hotel)
        .where(embedding_status: "indexing", hotels: { ai_provider_enabled: true })
        .where(updated_at: ..cutoff)
    end

    def recover(document)
      action = nil

      document.with_lock do
        document.reload
        next unless stale?(document)

        if document.metadata["indexing_recovery_attempts"].to_i >= MAX_RECOVERY_ATTEMPTS
          document.update!(
            embedding_status: "failed",
            metadata: document.metadata.merge("last_error" => TIMEOUT_ERROR)
          )
          action = :failed
        else
          document.update!(
            metadata: document.metadata.merge(
              "indexing_recovery_attempts" => 1,
              "indexing_recovered_at" => now.iso8601
            )
          )
          action = :retry
        end
      end

      if action == :retry
        HotelKnowledges::GenerateEmbeddingsJob.perform_later(document.id, recovery_attempt: 1)
      end
      action
    end

    def stale?(document)
      document.embedding_status == "indexing" &&
        document.hotel.ai_concierge_enabled? &&
        document.updated_at <= cutoff
    end

    def cutoff
      @cutoff ||= now - STALE_AFTER
    end
  end
end
