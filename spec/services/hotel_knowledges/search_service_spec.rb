# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::SearchService do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:query_vector) { [ 0.1 ] * 1536 }

  before do
    allow_any_instance_of(HotelKnowledges::EmbeddingService).to receive(:call).and_return([ query_vector ])
  end

  it "returns normalized nearest knowledge chunks for indexed documents in the requested categories" do
    doc = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "House Rules", embedding_status: "indexed", language: "en", version: 2)
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 0, content: "Check-in starts at 3 PM.", embedding: query_vector)
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 1, content: "Pets are not allowed.", embedding: ([ 0.1 ] * 768) + ([ -0.1 ] * 768))

    result = described_class.new(hotel: hotel, query: "what time is check in?", categories: [ "policy" ], limit: 1).call

    expect(result.size).to eq(1)
    expect(result.first).to include(
      "content" => "Check-in starts at 3 PM.",
      "document_title" => "House Rules",
      "category" => "policy",
      "language" => "en",
      "version" => 2,
      "chunk_index" => 0
    )
    expect(result.first).to have_key("distance")
  end

  it "ignores other hotels, categories, pending documents, and chunks without embeddings" do
    other_hotel = create(:hotel, :with_ai_concierge)
    matching_doc = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "FAQ", embedding_status: "indexed")
    pending_doc = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "Pending", embedding_status: "pending")
    other_category_doc = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Policy", embedding_status: "indexed")
    other_hotel_doc = create(:hotel_knowledge_document, hotel: other_hotel, category: "faq", title: "Other Hotel", embedding_status: "indexed")

    create(:hotel_knowledge_chunk, document: matching_doc, chunk_index: 0, content: "Breakfast is from 7 AM.", embedding: query_vector)
    create(:hotel_knowledge_chunk, document: matching_doc, chunk_index: 1, content: "No embedding.")
    create(:hotel_knowledge_chunk, document: pending_doc, chunk_index: 0, content: "Pending answer.", embedding: query_vector)
    create(:hotel_knowledge_chunk, document: other_category_doc, chunk_index: 0, content: "Policy answer.", embedding: query_vector)
    create(:hotel_knowledge_chunk, document: other_hotel_doc, chunk_index: 0, content: "Other answer.", embedding: query_vector)

    result = described_class.new(hotel: hotel, query: "breakfast?", categories: [ "faq" ]).call

    expect(result.map { |match| match["content"] }).to eq([ "Breakfast is from 7 AM." ])
  end

  it "returns an empty list when embedding generation fails" do
    allow_any_instance_of(HotelKnowledges::EmbeddingService).to receive(:call).and_raise(HotelKnowledges::EmbeddingError, "no key")

    result = described_class.new(hotel: hotel, query: "breakfast?", categories: [ "faq" ]).call

    expect(result).to eq([])
  end
end
