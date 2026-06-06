# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledgeDocument, type: :model do
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
    it { should validate_inclusion_of(:embedding_status).in_array(%w[pending indexed failed]) }
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
end
