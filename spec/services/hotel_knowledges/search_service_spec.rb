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

  # A hotel that published the same policy twice answers in the language the
  # guest is already speaking.
  it "breaks a tie toward the guest's language" do
    seed_same_policy_in_two_languages

    # Chinese, so keyword search contributes nothing and both chunks arrive on
    # the vector engine alone -- which is exactly when language should decide.
    prefers_malay = search("入住时间", preferred_language: "ms")
    prefers_english = search("入住时间", preferred_language: "en")

    expect(prefers_malay.first["language"]).to eq("ms")
    expect(prefers_english.first["language"]).to eq("en")
  end

  it "still offers the other language rather than filtering it away" do
    seed_same_policy_in_two_languages

    expect(search("入住时间", preferred_language: "ms").map { |row| row["language"] }).to contain_exactly("ms", "en")
  end

  # Preferred, never decisive. A chunk both engines found says more about the
  # question than the language it happens to be written in.
  it "does not outrank both engines agreeing on the other language" do
    seed_same_policy_in_two_languages

    expect(search("daftar masuk?", preferred_language: "en").first["language"]).to eq("ms")
  end

  def seed_same_policy_in_two_languages
    english = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "House Rules", embedding_status: "indexed", language: "en")
    malay = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "Peraturan", embedding_status: "indexed", language: "ms")
    create(:hotel_knowledge_chunk, document: english, chunk_index: 0, content: "Check-in starts at 3 PM.", embedding: query_vector)
    create(:hotel_knowledge_chunk, document: malay, chunk_index: 0, content: "Daftar masuk bermula 3 PM.", embedding: query_vector)
  end

  def search(query, preferred_language:)
    described_class.new(hotel: hotel, query: query, categories: [ "policy" ], preferred_language: preferred_language).call
  end

  it "returns an empty list when embedding generation fails" do
    allow_any_instance_of(HotelKnowledges::EmbeddingService).to receive(:call).and_raise(HotelKnowledges::EmbeddingError, "no key")

    result = described_class.new(hotel: hotel, query: "breakfast?", categories: [ "faq" ]).call

    expect(result).to eq([])
  end

  describe "fusing keyword search with vector search" do
    def indexed_document(category: "general_info", title: "Rooms")
      create(:hotel_knowledge_document, hotel: hotel, category: category, title: title, embedding_status: "indexed")
    end

    # The case hybrid retrieval exists for: the guest names a thing, the
    # nearest vector is a chunk about the same subject that does not name it.
    it "surfaces the chunk that names the thing even when the nearest vector does not" do
      document = indexed_document
      create(:hotel_knowledge_chunk, document: document, chunk_index: 0,
        content: "All rooms include air conditioning.", embedding: query_vector)
      create(:hotel_knowledge_chunk, document: document, chunk_index: 1,
        content: "The Deluxe Seaview has a private balcony.", embedding: ([ 0.1 ] * 768) + ([ -0.1 ] * 768))

      result = described_class.new(hotel: hotel, query: "Deluxe Seaview balcony", categories: [ "general_info" ]).call

      expect(result.map { |row| row["content"] }).to include("The Deluxe Seaview has a private balcony.")
    end

    it "says which retrievers found each chunk" do
      document = indexed_document
      create(:hotel_knowledge_chunk, document: document, chunk_index: 0,
        content: "Parking is free in the basement.", embedding: query_vector)

      result = described_class.new(hotel: hotel, query: "parking", categories: [ "general_info" ]).call

      expect(result.first["retrieval"]).to contain_exactly("vector", "keyword")
    end

    # A cosine distance is the only real number here. Inventing one for a row
    # keyword search found would be putting words in the retriever's mouth.
    it "leaves distance nil on a chunk only keyword search found" do
      document = indexed_document
      create(:hotel_knowledge_chunk, document: document, chunk_index: 0,
        content: "The Deluxe Seaview has a private balcony.", embedding: nil)

      result = described_class.new(hotel: hotel, query: "Deluxe Seaview", categories: [ "general_info" ]).call

      expect(result.first).to include("retrieval" => [ "keyword" ], "distance" => nil)
    end

    # Losing the embedding provider used to lose the whole answer.
    it "still finds by words when the question cannot be embedded" do
      allow_any_instance_of(HotelKnowledges::EmbeddingService)
        .to receive(:call).and_raise(HotelKnowledges::EmbeddingError, "provider down")

      document = indexed_document
      create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "Parking is free in the basement.")

      result = described_class.new(hotel: hotel, query: "parking", categories: [ "general_info" ]).call

      expect(result.first["content"]).to eq("Parking is free in the basement.")
    end
  end
end
