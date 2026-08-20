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

  # The same question in Chinese reaches none of the English word matches, and
  # this is the fastest and most certain answer the concierge has.
  it "answers a structured question the model named, in any language" do
    result = described_class.new(
      hotel: hotel,
      query: "几点入住?",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "property_policy",
      structured_facts: { "check_in_time" => "3:00 PM" },
      hints: AiConcierge::Retrieval::QueryHints.new(fact: "check_in_time"),
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result["answer"]).to eq("Check-in starts at 3:00 PM.")
    expect(result["answer_mode"]).to eq("fallback")
  end

  it "ignores a named fact the hotel has not filled in" do
    result = described_class.new(
      hotel: hotel,
      query: "几点入住?",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "property_policy",
      structured_facts: {},
      hints: AiConcierge::Retrieval::QueryHints.new(fact: "check_in_time"),
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result["answer_mode"]).to eq("unavailable")
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

  # Two retrievers agreeing is a better reason to quote a chunk verbatim than
  # any distance threshold, because they fail differently.
  it "quotes a chunk both retrievers found, even without a strong distance" do
    agreed = match.merge("distance" => 0.9, "retrieval" => [ "vector", "keyword" ])

    result = described_class.new(
      hotel: hotel,
      query: "what time is breakfast?",
      intent: "hotel_information",
      topic: "hotel_faq",
      categories: [ "faq" ],
      source: "hotel_faq",
      search_service: search_service_returning([ agreed ]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result).to include("answer_mode" => "deterministic", "answer" => match["content"])
  end

  # A chunk only keyword search found matched some words -- that is how it got
  # here -- but nothing has vouched for what it means, so it is not quoted at
  # the guest on its own.
  it "does not quote a chunk only keyword search found" do
    keyword_only = match.merge("distance" => nil, "retrieval" => [ "keyword" ])

    result = described_class.new(
      hotel: hotel,
      query: "what time is breakfast?",
      intent: "hotel_information",
      topic: "hotel_faq",
      categories: [ "faq" ],
      source: "hotel_faq",
      fallback_text: "Please ask the front desk.",
      search_service: search_service_returning([ keyword_only ]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result["answer_mode"]).not_to eq("deterministic")
  end

  describe "caching the answer" do
    it "answers a repeated question without searching again" do
      with_real_cache_store do
        search_service = search_service_returning([ match ])
        allow(search_service).to receive(:new).and_call_original

        2.times do
          described_class.new(
            hotel: hotel,
            query: "what time is breakfast?",
            intent: "hotel_information",
            topic: "hotel_faq",
            categories: [ "faq" ],
            source: "hotel_faq",
            search_service: search_service,
            answer_agent: answer_agent_returning("unused")
          ).call
        end

        expect(search_service).to have_received(:new).once
      end
    end

    # A hotel that changes its check-in time must not keep being asked to
    # honour the old one.
    it "stops serving an answer once the facts behind it change" do
      with_real_cache_store do
        def build(check_in)
          described_class.new(
            hotel: hotel,
            query: "what time is check in?",
            intent: "hotel_policy",
            topic: "hotel_policy",
            categories: [ "policy" ],
            source: "property_policy",
            structured_facts: { "check_in_time" => check_in },
            search_service: search_service_returning([]),
            answer_agent: answer_agent_returning("unused")
          ).call
        end

        expect(build("3:00 PM")["answer"]).to eq("Check-in starts at 3:00 PM.")
        expect(build("2:00 PM")["answer"]).to eq("Check-in starts at 2:00 PM.")
      end
    end

    it "stops serving an answer once the hotel re-ingests its knowledge" do
      with_real_cache_store do
        document = create(:hotel_knowledge_document, hotel: hotel, category: "faq", embedding_status: "indexed")

        first = described_class.new(
          hotel: hotel, query: "what time is breakfast?", intent: "hotel_information",
          topic: "hotel_faq", categories: [ "faq" ], source: "hotel_faq",
          search_service: search_service_returning([ match ]),
          answer_agent: answer_agent_returning("unused")
        ).call

        travel_to(1.hour.from_now) { document.touch }

        second = described_class.new(
          hotel: hotel, query: "what time is breakfast?", intent: "hotel_information",
          topic: "hotel_faq", categories: [ "faq" ], source: "hotel_faq",
          search_service: search_service_returning([ match.merge("content" => "Breakfast now runs to 11 AM.") ]),
          answer_agent: answer_agent_returning("unused")
        ).call

        expect(first["answer"]).to eq("Breakfast is served from 7 AM to 10 AM.")
        expect(second["answer"]).to eq("Breakfast now runs to 11 AM.")
      end
    end
  end
end
