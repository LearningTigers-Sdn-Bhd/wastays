# frozen_string_literal: true

module HotelKnowledges
  class GenerateEmbeddingsJob < ApplicationJob
    queue_as :ai_concierge

    discard_on ActiveJob::DeserializationError

    def perform(document_id)
      document = HotelKnowledgeDocument.find_by(id: document_id)
      return unless document

      KnowledgeIngestionService.new(document).call
    rescue HotelKnowledges::IngestionError => e
      document.update!(embedding_status: "failed", metadata: document.metadata.merge("last_error" => e.message))
      raise
    end
  end
end
