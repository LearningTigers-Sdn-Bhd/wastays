# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::GenerateEmbeddingsJob do
  describe "#perform" do
    let(:hotel) { create(:hotel) }
    let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "text", content: "Hello world") }

    before do
      allow(HotelKnowledges::KnowledgeIngestionService).to receive_message_chain(:new, :call)
    end

    it "calls KnowledgeIngestionService" do
      described_class.perform_now(document.id)
      expect(HotelKnowledges::KnowledgeIngestionService).to have_received(:new).with(document)
    end

    it "marks the document indexing before ingestion starts" do
      document.update_column(:embedding_status, "failed")

      described_class.perform_now(document.id)

      expect(document.reload.embedding_status).to eq("indexing")
    end

    it "handles non-existent document gracefully" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end

    context "when ingestion fails" do
      it "marks document as failed" do
        allow(HotelKnowledges::KnowledgeIngestionService).to receive_message_chain(:new, :call)
          .and_raise(HotelKnowledges::IngestionError.new("API failure"))

        expect { described_class.perform_now(document.id) }.to raise_error(HotelKnowledges::IngestionError)
        expect(document.reload.embedding_status).to eq("failed")
        expect(document.metadata["last_error"]).to eq("API failure")
      end
    end
  end

  describe "queue" do
    it "uses the ai_concierge queue" do
      expect(described_class.new.queue_name).to eq("ai_concierge")
    end
  end
end
