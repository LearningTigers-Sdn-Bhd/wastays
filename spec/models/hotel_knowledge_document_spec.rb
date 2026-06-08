# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledgeDocument, type: :model do
  include ActiveJob::TestHelper

  describe "associations" do
    it { should belong_to(:hotel) }
    it { should have_many(:chunks).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:hotel_knowledge_document) }

    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:source_type) }
    it { should validate_presence_of(:category) }
    it { should validate_inclusion_of(:source_type).in_array(%w[text pdf]) }
    it { should validate_inclusion_of(:category).in_array(%w[policy faq general_info]) }
    it { should validate_inclusion_of(:embedding_status).in_array(%w[pending indexing indexed failed]) }
  end

  describe "defaults" do
    it "sets default language" do
      doc = build(:hotel_knowledge_document)
      expect(doc.language).to eq("en")
    end

    it "sets default embedding_status" do
      doc = build(:hotel_knowledge_document)
      expect(doc.embedding_status).to eq("pending")
    end

    it "sets default version" do
      doc = build(:hotel_knowledge_document)
      expect(doc.version).to eq(1)
    end

    it "sets default tags" do
      doc = build(:hotel_knowledge_document)
      expect(doc.tags).to eq([])
    end
  end

  describe "chunks" do
    it "destroys associated chunks when document is destroyed" do
      doc = create(:hotel_knowledge_document)
      doc.chunks.create!(content: "Test", chunk_index: 0)

      expect { doc.destroy! }.to change(HotelKnowledgeChunk, :count).by(-1)
    end
  end

  describe "#enqueue_embedding_generation!" do
    let(:hotel) do
      create(:hotel, ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "sk-test-key")
    end

    it "marks the document indexing, clears the last error, and enqueues embedding generation" do
      doc = create(
        :hotel_knowledge_document,
        hotel: hotel,
        embedding_status: "failed",
        metadata: { "last_error" => "Previous failure" }
      )

      expect {
        doc.enqueue_embedding_generation!
      }.to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob).with(doc.id)

      expect(doc.reload.embedding_status).to eq("indexing")
      expect(doc.metadata).not_to have_key("last_error")
    end
  end

  describe "automatic embedding generation" do
    it "does not enqueue another job when an attached PDF finishes indexing" do
      hotel = create(
        :hotel,
        ai_provider_enabled: true,
        ai_provider_name: "openai",
        ai_provider_key: "sk-test-key"
      )
      doc = create(:hotel_knowledge_document, hotel: hotel, source_type: "pdf")
      doc.file.attach(
        io: StringIO.new("%PDF-1.4 test"),
        filename: "knowledge.pdf",
        content_type: "application/pdf"
      )
      clear_enqueued_jobs

      expect {
        doc.update!(embedding_status: "indexed")
      }.not_to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob)
    end
  end

  describe "embedding state broadcasts" do
    it "broadcasts a Turbo refresh when the embedding status changes" do
      doc = create(:hotel_knowledge_document)
      allow(doc).to receive(:broadcast_refresh_to)

      doc.update!(embedding_status: "indexed")

      expect(doc).to have_received(:broadcast_refresh_to).with(doc)
    end

    it "does not broadcast a Turbo refresh for unrelated updates" do
      doc = create(:hotel_knowledge_document)
      allow(doc).to receive(:broadcast_refresh_to)

      doc.update!(title: "Updated title")

      expect(doc).not_to have_received(:broadcast_refresh_to)
    end
  end
end
