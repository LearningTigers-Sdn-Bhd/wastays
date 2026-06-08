# frozen_string_literal: true

module HotelKnowledges
  class EmbeddingError < StandardError; end

  class EmbeddingService
    MODEL = "text-embedding-3-small"
    DIMENSIONS = 1536
    BATCH_SIZE = 20

    def initialize(hotel:)
      @hotel = hotel
    end

    def call(texts)
      texts = Array(texts)
      return [] if texts.empty?

      context = RubyLLM.context do |config|
        config.openai_api_key = embedding_api_key
      end

      results = []
      texts.each_slice(BATCH_SIZE) do |batch|
        response = RubyLLM::Embedding.embed(
          batch,
          model: MODEL,
          dimensions: DIMENSIONS,
          context: context
        )
        vectors = response.vectors
        results.concat(vectors)
      end

      results
    rescue RubyLLM::Error => e
      raise EmbeddingError, "Embedding API error: #{e.message}"
    end

    private

    attr_reader :hotel

    def embedding_api_key
      raise EmbeddingError, "AI Concierge is not enabled for embeddings" unless hotel.ai_concierge_enabled?

      if hotel.ai_provider_name == "openai" && hotel.ai_concierge_api_key.present?
        hotel.ai_concierge_api_key
      else
        AppConfig.get("openai_api_key") or
          raise EmbeddingError, "No OpenAI API key available for embeddings"
      end
    end
  end
end
