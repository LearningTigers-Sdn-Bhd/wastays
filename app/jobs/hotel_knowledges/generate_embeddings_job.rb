# frozen_string_literal: true

module HotelKnowledges
  class GenerateEmbeddingsJob < ApplicationJob
    queue_as :ai_concierge

    discard_on ActiveJob::DeserializationError

    def perform(document_id, recovery_attempt: nil)
      document = HotelKnowledgeDocument.find_by(id: document_id)
      return unless document
      return if recovery_attempt.present? && !current_recovery?(document, recovery_attempt)

      document.mark_embedding_indexing!
      KnowledgeIngestionService.new(document).call
    rescue HotelKnowledges::IngestionError => e
      document.update!(embedding_status: "failed", metadata: document.metadata.merge("last_error" => e.message))
      raise
    end

    private

    def current_recovery?(document, recovery_attempt)
      document.embedding_status == "indexing" &&
        document.metadata["indexing_recovery_attempts"].to_i == recovery_attempt.to_i
    end
  end
end
