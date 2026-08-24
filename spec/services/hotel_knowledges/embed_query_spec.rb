# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::EmbedQuery do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:vector) { [ 0.1 ] * 1536 }

  it "returns the embedding for the question" do
    allow_any_instance_of(HotelKnowledges::EmbeddingService).to receive(:call).and_return([ vector ])

    expect(described_class.new(hotel: hotel, query: "what time is check in?").call).to eq(vector)
  end

  it "returns nothing for a blank question without calling the provider" do
    embedding_service = instance_spy(HotelKnowledges::EmbeddingService)
    allow(HotelKnowledges::EmbeddingService).to receive(:new).and_return(embedding_service)

    expect(described_class.new(hotel: hotel, query: "   ").call).to be_nil
    expect(embedding_service).not_to have_received(:call)
  end

  # The test env runs a null store, so a caching bug is invisible without a
  # real one -- see spec/support/real_cache_store.rb.
  it "asks the provider once for a question that repeats" do
    with_real_cache_store do
      embedding_service = instance_spy(HotelKnowledges::EmbeddingService, call: [ vector ])
      allow(HotelKnowledges::EmbeddingService).to receive(:new).and_return(embedding_service)

      3.times { described_class.new(hotel: hotel, query: "What time is check in?").call }

      expect(embedding_service).to have_received(:call).once
    end
  end

  # An embedding depends on the model, not on who is asking. Scoping the cache
  # per hotel would make every hotel pay again for "do you have parking".
  it "shares a cached vector across hotels and across casing" do
    with_real_cache_store do
      embedding_service = instance_spy(HotelKnowledges::EmbeddingService, call: [ vector ])
      allow(HotelKnowledges::EmbeddingService).to receive(:new).and_return(embedding_service)

      described_class.new(hotel: hotel, query: "Do you have parking?").call
      described_class.new(hotel: create(:hotel, :with_ai_concierge), query: "do you have parking?").call

      expect(embedding_service).to have_received(:call).once
    end
  end

  # A provider outage must not be remembered as an answer.
  it "does not cache a failure" do
    with_real_cache_store do
      call_count = 0
      allow_any_instance_of(HotelKnowledges::EmbeddingService).to receive(:call) do
        call_count += 1
        raise HotelKnowledges::EmbeddingError, "provider down"
      end

      2.times do
        expect { described_class.new(hotel: hotel, query: "is there a pool?").call }
          .to raise_error(HotelKnowledges::EmbeddingError)
      end

      expect(call_count).to eq(2)
    end
  end
end
