# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::KnowledgeIngestionService do
  subject(:service) { described_class.new(document) }

  let(:hotel) { create(:hotel) }

  describe "#call" do
    before do
      allow(HotelKnowledges::EmbeddingService).to receive_message_chain(:new, :call) do |texts|
        texts.map { |t| [0.1] * 1536 }
      end
    end

    context "with a text document" do
      let(:long_para) { "Paragraph with lots of words. " * 180 }
      let(:content) { "#{long_para}\n\n#{long_para}" }
      let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "text", content: content) }

      it "creates chunks" do
        expect { service.call }.to change { document.chunks.count }.from(0).to(4)
      end

      it "sets embedding_status to indexed" do
        service.call
        expect(document.reload.embedding_status).to eq("indexed")
      end

      it "assigns embeddings to chunks" do
        service.call
        expect(document.chunks.pluck(:embedding)).to all(be_present)
      end

      it "assigns token counts" do
        service.call
        expect(document.chunks.pluck(:token_count)).to all(be > 0)
      end
    end

    context "with an empty content document" do
      let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "text", content: "") }

      it "sets embedding_status to indexed without creating chunks" do
        service.call
        expect(document.reload.embedding_status).to eq("indexed")
        expect(document.chunks.count).to eq(0)
      end
    end

    context "with a PDF document" do
      let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "pdf") }

      before do
        allow(HotelKnowledges::PdfParsingService).to receive_message_chain(:new, :call)
          .and_return("Extracted PDF text here.\n\nMore PDF content.")
        allow(HotelKnowledges::ChunkingService).to receive_message_chain(:new, :call)
          .and_return([
            { content: "Extracted PDF text here.", chunk_index: 0 },
            { content: "More PDF content.", chunk_index: 1 }
          ])

        file = StringIO.new("fake pdf content")
        document.file.attach(io: file, filename: "test.pdf", content_type: "application/pdf")
      end

      it "parses the PDF and creates chunks" do
        expect { service.call }.to change { document.chunks.count }.from(0).to(2)
      end

      it "sets embedding_status to indexed" do
        service.call
        expect(document.reload.embedding_status).to eq("indexed")
      end
    end

    context "with a PDF document that has no file attached" do
      let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "pdf") }

      it "sets embedding_status to failed" do
        expect { service.call }.to raise_error(HotelKnowledges::IngestionError)
        expect(document.reload.embedding_status).to eq("failed")
      end

      it "stores the error in metadata" do
        expect { service.call }.to raise_error(HotelKnowledges::IngestionError)
        expect(document.reload.metadata["last_error"]).to be_present
      end
    end

    context "when embedding service fails" do
      let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "text", content: "Some content") }

      before do
        allow(HotelKnowledges::EmbeddingService).to receive_message_chain(:new, :call)
          .and_raise(HotelKnowledges::EmbeddingError.new("API failure"))
      end

      it "sets embedding_status to failed" do
        expect { service.call }.to raise_error(HotelKnowledges::IngestionError)
        expect(document.reload.embedding_status).to eq("failed")
      end

      it "stores the error message in metadata" do
        expect { service.call }.to raise_error(HotelKnowledges::IngestionError)
        expect(document.reload.metadata["last_error"]).to eq("API failure")
      end
    end

    context "with existing chunks" do
      let(:document) { create(:hotel_knowledge_document, hotel: hotel, source_type: "text", content: "New content") }

      before do
        document.chunks.create!(content: "Old chunk", chunk_index: 0)
      end

      it "replaces existing chunks" do
        service.call
        document.chunks.reload
        expect(document.chunks.count).to eq(1)
        expect(document.chunks.first.content).to eq("New content")
      end
    end
  end
end
