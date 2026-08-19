# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Tools::HotelInformation::HybridAnswerBuilder do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:query_vector) { [ 0.1 ] * 1536 }

  before do
    allow_any_instance_of(HotelKnowledges::EmbeddingService).to receive(:call).and_return([ query_vector ])
  end

  let(:match) do
    {
      "content" => "Breakfast is served from 7 AM to 10 AM.",
      "document_title" => "Dining",
      "category" => "faq",
      "distance" => 0.12
    }
  end

  def search_service_returning(matches)
    Class.new do
      define_singleton_method(:matches) { matches }

      def initialize(*)
      end

      def call
        self.class.matches
      end
    end
  end

  def search_service_by_categories(results)
    Class.new do
      define_singleton_method(:results) { results }

      def initialize(hotel:, query:, categories:, **)
        @categories = Array(categories).map(&:to_s).sort.join(",")
      end

      def call
        self.class.results.fetch(@categories, [])
      end
    end
  end

  def answer_agent_returning(answer)
    Class.new do
      define_singleton_method(:answer) { answer }

      def initialize(*)
      end

      def call
        self.class.answer
      end
    end
  end

  it "uses deterministic mode for one strong match" do
    result = described_class.new(
      hotel: hotel,
      query: "what time is breakfast?",
      intent: "hotel_information",
      topic: "hotel_faq",
      categories: [ "faq" ],
      source: "hotel_faq",
      search_service: search_service_returning([ match ]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result).to include(
      "success" => true,
      "answer" => "Breakfast is served from 7 AM to 10 AM.",
      "answer_mode" => "deterministic",
      "source" => "hotel_faq"
    )
    expect(result["knowledge_matches"]).to eq([ match ])
  end

  it "uses synthesis mode for multiple matches" do
    second_match = match.merge("content" => "Parking is available for guests.", "distance" => 0.2)

    result = described_class.new(
      hotel: hotel,
      query: "tell me about breakfast and parking",
      intent: "hotel_information",
      topic: "hotel_faq",
      categories: [ "faq" ],
      source: "hotel_faq",
      search_service: search_service_returning([ match, second_match ]),
      answer_agent: answer_agent_returning("Breakfast runs from 7 AM to 10 AM, and parking is available.")
    ).call

    expect(result["answer_mode"]).to eq("synthesized")
    expect(result["answer"]).to eq("Breakfast runs from 7 AM to 10 AM, and parking is available.")
  end

  it "answers direct structured policy questions without synthesis" do
    result = described_class.new(
      hotel: hotel,
      query: "what time is check in?",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "property_policy",
      structured_facts: { "check_in_time" => "3:00 PM" },
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result["answer"]).to eq("Check-in starts at 3:00 PM.")
    expect(result["answer_mode"]).to eq("fallback")
  end

  it "falls back to the best deterministic match when synthesis fails" do
    failing_agent = Class.new do
      def initialize(*)
      end

      def call
        raise AiConcierge::Agents::KnowledgeAnswerAgent::KnowledgeAnswerError, "timeout"
      end
    end

    result = described_class.new(
      hotel: hotel,
      query: "tell me about breakfast and parking",
      intent: "hotel_information",
      topic: "hotel_faq",
      categories: [ "faq" ],
      source: "hotel_faq",
      search_service: search_service_returning([ match, match.merge("content" => "Parking is available.") ]),
      answer_agent: failing_agent
    ).call

    expect(result["answer"]).to eq("Breakfast is served from 7 AM to 10 AM.")
    expect(result["answer_mode"]).to eq("deterministic")
  end

  it "searches all hotel knowledge categories before using generic fallback text" do
    parking_match = match.merge(
      "content" => "Parking is available for in-house guests.",
      "category" => "faq",
      "distance" => 0.11
    )

    result = described_class.new(
      hotel: hotel,
      query: "is parking available there?",
      intent: "hotel_information",
      topic: "general_hotel_info",
      categories: [ "general_info" ],
      source: "general_hotel_info",
      fallback_text: "Generic hotel summary.",
      search_service: search_service_by_categories(
        "general_info" => [],
        "faq,general_info,policy" => [ parking_match ]
      ),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result["answer"]).to eq("Parking is available for in-house guests.")
    expect(result["answer_mode"]).to eq("deterministic")
    expect(result["knowledge_matches"].first["category"]).to eq("faq")
  end

  it "retries all categories when the routed category has only a weak single match" do
    weak_match = match.merge("content" => "Generic hotel details.", "category" => "general_info", "distance" => 0.8)
    parking_match = match.merge("content" => "Parking is free.", "category" => "faq", "distance" => 0.1)

    result = described_class.new(
      hotel: hotel,
      query: "is parking available there?",
      intent: "hotel_information",
      topic: "general_hotel_info",
      categories: [ "general_info" ],
      source: "general_hotel_info",
      search_service: search_service_by_categories(
        "general_info" => [ weak_match ],
        "faq,general_info,policy" => [ parking_match ]
      ),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result["answer"]).to eq("Parking is free.")
  end

  it "returns unavailable mode when no match or fallback exists" do
    result = described_class.new(
      hotel: hotel,
      query: "do you have a helipad?",
      intent: "hotel_information",
      topic: "hotel_faq",
      categories: [ "faq" ],
      source: "hotel_faq",
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result).to include(
      "success" => false,
      "answer_mode" => "unavailable"
    )
  end

  # A thin first pass searches a second time over the fallback categories.
  # Both passes ask about the same sentence, so there is only one vector to
  # compute -- this used to be two round-trips to an embedding API on the
  # slowest path the concierge has. The real search service is used here on
  # purpose: the point of the example is what reaches the provider.
  it "embeds the question once even when it falls back to a second search" do
    with_real_cache_store do
      embedding_service = instance_spy(HotelKnowledges::EmbeddingService, call: [ query_vector ])
      allow(HotelKnowledges::EmbeddingService).to receive(:new).and_return(embedding_service)

      described_class.new(
        hotel: hotel,
        query: "is there parking?",
        intent: "hotel_information",
        topic: "general_hotel_info",
        categories: [ "general_info" ],
        source: "general_hotel_info",
        answer_agent: answer_agent_returning("unused")
      ).call

      expect(embedding_service).to have_received(:call).once
    end
  end
end
