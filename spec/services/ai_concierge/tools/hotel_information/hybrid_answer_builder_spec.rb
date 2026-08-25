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

    expect(result).to have_attributes(success: true, answer_mode: "deterministic", source: "hotel_faq")
    expect(result.facts.map(&:text)).to eq([ "Breakfast is served from 7 AM to 10 AM." ])
    expect(result.knowledge_matches).to eq([ match ])
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

    expect(result.answer_mode).to eq("synthesized")
    expect(result.facts.map(&:text)).to eq([ "Breakfast runs from 7 AM to 10 AM, and parking is available." ])
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

    expect(result.facts.map(&:text)).to eq([ "You can check in from 3:00 PM." ])
    expect(result.answer_mode).to eq("structured")
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

    expect(result.facts.map(&:text)).to eq([ "You can check in from 3:00 PM." ])
    expect(result.answer_mode).to eq("structured")
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

    expect(result.answer_mode).to eq("unavailable")
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

    expect(result.facts.map(&:text)).to eq([ "Breakfast is served from 7 AM to 10 AM." ])
    expect(result.answer_mode).to eq("fallback")
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

    expect(result.facts.map(&:text)).to eq([ "Parking is available for in-house guests." ])
    expect(result.answer_mode).to eq("deterministic")
    expect(result.knowledge_matches.first["category"]).to eq("faq")
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

    expect(result.facts.map(&:text)).to eq([ "Parking is free." ])
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

    expect(result).to have_attributes(success: false, answer_mode: "unavailable")
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

    expect(result).to have_attributes(answer_mode: "deterministic")
    expect(result.facts.map(&:text)).to eq([ match["content"] ])
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

    expect(result.answer_mode).not_to eq("deterministic")
  end

  it "returns at most five structured facts for a broad policy question and names the remaining topics" do
    synthesized = (1..4).map do |index|
      AiConcierge::Orchestration::HotelKnowledge::Reply::Fact.new(
        topic: "rule #{index}", text: "Rule #{index} applies.", source_refs: [ index ]
      )
    end
    matches = synthesized.each_with_index.map do |_, index|
      match.merge("content" => "Rule #{index + 1} applies.", "distance" => 0.1 + index.fdiv(100))
    end

    result = described_class.new(
      hotel: hotel,
      query: "what are all your hotel policies?",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "hotel_policy",
      scope: "broad",
      structured_facts: {
        "check_in_time" => "3:00 PM",
        "check_out_time" => "11:00 AM",
        "cancellation_policy" => "Free until 24 hours before arrival"
      },
      search_service: search_service_returning(matches),
      answer_agent: answer_agent_returning(synthesized)
    ).call

    expect(result.shape).to eq("list")
    expect(result.facts.size).to eq(5)
    expect(result.remaining_topics).to eq([ "rule 3", "rule 4" ])
    expect(result.facts.map(&:text).join(" ")).not_to include("not provided")
  end

  it "omits missing structured fields from a broad policy reply" do
    result = described_class.new(
      hotel: hotel,
      query: "what is the hotel policy?",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "property_policy",
      scope: "broad",
      structured_facts: { "check_in_time" => "3:00 PM", "check_out_time" => nil },
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result.shape).to eq("list")
    expect(result.facts.map(&:topic)).to eq([ "check-in" ])
  end

  it "asks one focused question when a specific policy request is ambiguous" do
    result = described_class.new(
      hotel: hotel,
      query: "what policy applies?",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "property_policy",
      scope: "specific",
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result).to have_attributes(shape: "clarification", answer_mode: "unavailable", success: false)
    expect(result.facts.one?).to be(true)
    expect(result.facts.first.text).to end_with("?")
  end

  it "clarifies ambiguous opening hours even when the model hints at check-in" do
    result = described_class.new(
      hotel: hotel,
      query: "what hour you start open",
      intent: "hotel_policy",
      topic: "hotel_policy",
      categories: [ "policy" ],
      source: "property_policy",
      structured_facts: { "check_in_time" => "3:00 PM" },
      hints: AiConcierge::Retrieval::QueryHints.new(fact: "check_in_time"),
      search_service: search_service_returning([]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result).to have_attributes(shape: "clarification", success: false)
    expect(result.facts.first.text).to eq("Do you mean the hotel check-in time or the opening hours of a facility?")
  end

  it "clarifies ambiguous opening hours before reading a stale cached answer" do
    with_real_cache_store do
      builder = described_class.new(
        hotel: hotel,
        query: "what hour you start open",
        intent: "hotel_information",
        topic: "general_hotel_info",
        categories: [ "general_info" ],
        source: "general_hotel_info",
        search_service: search_service_returning([]),
        answer_agent: answer_agent_returning("unused")
      )
      stale = AiConcierge::Orchestration::HotelKnowledge::Reply.new(
        shape: "direct",
        answer_mode: "synthesized",
        facts: [ AiConcierge::Orchestration::HotelKnowledge::Reply::Fact.new(text: "Check-in time is from 3:00 PM.") ]
      )
      Rails.cache.write(builder.send(:cache_key), stale.to_h)

      result = builder.call

      expect(result).to have_attributes(shape: "clarification", success: false)
      expect(result.facts.first.text).to start_with("Do you mean")
    end
  end

  it "does not clarify opening hours when the guest names a facility" do
    result = described_class.new(
      hotel: hotel,
      query: "what time does the pool open?",
      intent: "hotel_information",
      topic: "general_hotel_info",
      categories: [ "general_info" ],
      source: "general_hotel_info",
      search_service: search_service_returning([
        match.merge("content" => "The pool opens at 7:00 AM.", "document_title" => "Pool")
      ]),
      answer_agent: answer_agent_returning("unused")
    ).call

    expect(result).to have_attributes(shape: "direct", answer_mode: "deterministic", success: true)
    expect(result.facts.first.text).to eq("The pool opens at 7:00 AM.")
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

        expect(build("3:00 PM").facts.map(&:text)).to eq([ "You can check in from 3:00 PM." ])
        expect(build("2:00 PM").facts.map(&:text)).to eq([ "You can check in from 2:00 PM." ])
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

        expect(first.facts.map(&:text)).to eq([ "Breakfast is served from 7 AM to 10 AM." ])
        expect(second.facts.map(&:text)).to eq([ "Breakfast now runs to 11 AM." ])
      end
    end
  end
end
