# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::KeywordSearchService do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  def indexed_document(category: "general_info", title: "Rooms")
    create(:hotel_knowledge_document, hotel: hotel, category: category, title: title, embedding_status: "indexed")
  end

  it "finds the chunk that names the thing the guest named" do
    document = indexed_document
    create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "The Deluxe Seaview room has a private balcony.")
    create(:hotel_knowledge_chunk, document: document, chunk_index: 1, content: "All rooms include air conditioning and a safe.")

    result = described_class.new(hotel: hotel, query: "tell me about the Deluxe Seaview", categories: [ "general_info" ]).call

    expect(result.first["content"]).to include("Deluxe Seaview")
  end

  # Requiring every word would mean a guest who writes a sentence instead of a
  # search box gets nothing, and that is most guests.
  it "matches on the words that carry meaning rather than all of them" do
    document = indexed_document
    create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "Parking is free in the basement.")

    result = described_class.new(hotel: hotel, query: "hi, could you tell me whether there is any parking?", categories: [ "general_info" ]).call

    expect(result.first["content"]).to eq("Parking is free in the basement.")
  end

  # A Chinese question has no spaces in it, so it tokenises into one long
  # non-word and matches nothing -- and would match nothing even against a
  # Chinese document, because the index cannot split it either.
  it "finds nothing for a question written in another language" do
    document = indexed_document
    create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "Parking is free in the basement.")

    expect(described_class.new(hotel: hotel, query: "停车费多少钱", categories: [ "general_info" ]).call).to eq([])
  end

  it "finds it once the question arrives with terms in the document's language" do
    document = indexed_document
    create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "Parking is free in the basement.")

    result = described_class.new(
      hotel: hotel,
      query: "停车费多少钱",
      categories: [ "general_info" ],
      extra_terms: [ "parking cost" ]
    ).call

    expect(result.first["content"]).to eq("Parking is free in the basement.")
  end

  it "returns nothing when the question carries no searchable words" do
    document = indexed_document
    create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "Parking is free in the basement.")

    expect(described_class.new(hotel: hotel, query: "is it ok?", categories: [ "general_info" ]).call).to eq([])
  end

  it "never lets a guest's punctuation reach the query parser" do
    document = indexed_document
    create(:hotel_knowledge_chunk, document: document, chunk_index: 0, content: "Breakfast runs until 10 AM.")

    expect {
      described_class.new(hotel: hotel, query: "breakfast & ! (parking) <-> 'quotes'", categories: [ "general_info" ]).call
    }.not_to raise_error
  end

  it "stays inside its own hotel, category and indexed documents" do
    other_hotel_document = create(:hotel_knowledge_document, hotel: create(:hotel), category: "general_info", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: other_hotel_document, content: "Parking is free at the other hotel.")

    unindexed = indexed_document
    unindexed.update_columns(embedding_status: "pending")
    create(:hotel_knowledge_chunk, document: unindexed, content: "Parking is free but not yet indexed.")

    create(:hotel_knowledge_chunk, document: indexed_document(category: "policy", title: "Rules"), content: "Parking is free in the basement.")

    result = described_class.new(hotel: hotel, query: "parking", categories: [ "general_info" ]).call

    expect(result).to eq([])
  end
end
