# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledgeChunk, type: :model do
  describe "associations" do
    it { should belong_to(:document).class_name("HotelKnowledgeDocument") }
  end

  describe "neighbors" do
    it "responds to has_neighbors" do
      doc = create(:hotel_knowledge_document)
      chunk = doc.chunks.create!(content: "Test", chunk_index: 0)
      expect(chunk).to respond_to(:nearest_neighbors)
    end
  end
end
