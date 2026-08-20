# frozen_string_literal: true

# Drives a conversation fixture through the real concierge entry point.
#
# Only the model is faked. Everything below it is real: Postgres conversation
# state, Booking::Orchestrator, the message builders, the prospect_messages
# rows. That is deliberate -- a harness that stubs the domain would go green on
# a rewrite that broke the domain, which is exactly the failure it exists to
# catch.
module AiConciergeEval
  module PipelineDriver
    TurnResult = Struct.new(:result, :prospect, :conversation_state, :quotes_created, keyword_init: true) do
      def payload = result.payload || {}
      def reply = payload[:reply_message]
      def slots_payload = conversation_state.slots_payload
      def booking_task = slots_payload["booking_task"] || {}
    end

    # `stylist` is how a fixture run says what the reply stylist gives back --
    # the same keywords stub_concierge_stylist takes. Left out, replies come
    # through as the templates wrote them, which is what a hotel on the default
    # tone answering an English guest gets.
    def run_fixture(fixture, stylist: nil)
      world = build_fixture_world(fixture)
      install_model_fake(fixture, world)
      stub_concierge_stylist(**stylist) if stylist

      fixture.turns.each_with_index do |turn, index|
        yield turn, post_fixture_turn(world, turn), index
      end
    end

    private

    def build_fixture_world(fixture)
      hotel = create(:hotel, :with_ai_concierge)
      policy = fixture.setup["policy"] || {}
      create(
        :property_policy,
        hotel: hotel,
        check_in_time: policy.fetch("check_in_time", "15:00"),
        check_out_time: policy.fetch("check_out_time", "12:00"),
        cancellation_policy: policy.fetch("cancellation_policy", "Free cancellation up to 24 hours before arrival.")
      )

      room_type_names = Array(fixture.setup["rooms"]).map { |room| seed_fixture_room(hotel, room) }
      corpus = Array(fixture.setup["knowledge"]).flat_map { |document| seed_fixture_knowledge(hotel, document) }
      install_knowledge_fake(corpus)

      prospect = create(:prospect, hotel: hotel)
      create_fixture_state(prospect, fixture.setup["state"])

      { hotel: hotel, prospect: prospect, room_type_names: room_type_names }
    end

    def seed_fixture_room(hotel, room)
      room_type = create(
        :room_type,
        hotel: hotel,
        name: room.fetch("name"),
        base_price: room.fetch("base_price", 180),
        max_adults: room.fetch("max_adults", 2)
      )

      month = room.fetch("month")
      year = fixture_year_for(month)
      Array(room.fetch("days")).each_with_index do |day, index|
        date = Date.new(year, month, day)
        create(:room_rate, room_type: room_type, date: date, price: 220 + index, currency: "MYR")
        create(:room_inventory, room_type: room_type, date: date, quantity: 2, status: "open")
      end

      room_type.name
    end

    def seed_fixture_knowledge(hotel, document)
      record = create(
        :hotel_knowledge_document,
        hotel: hotel,
        category: document.fetch("category"),
        title: document.fetch("title"),
        embedding_status: "indexed"
      )

      Array(document.fetch("chunks")).each_with_index.map do |content, index|
        create(:hotel_knowledge_chunk, document: record, chunk_index: index, content: content)
        {
          "content" => content,
          "document_title" => record.title,
          "category" => record.category,
          "language" => record.language,
          "version" => record.version,
          "chunk_index" => index
        }
      end
    end

    def create_fixture_state(prospect, state)
      trait = (state || {})["trait"]&.to_sym
      return create(:prospect_conversation_state, prospect: prospect) if trait.blank? || trait == :fresh

      create(:prospect_conversation_state, trait, prospect: prospect)
    end

    # Retrieval without an embedding provider: score the seeded corpus by word
    # overlap and hand back the same row shape SearchService produces, distance
    # included, because HybridAnswerBuilder's deterministic short-circuit reads
    # it (STRONG_MATCH_DISTANCE = 0.35).
    def install_knowledge_fake(corpus)
      allow(HotelKnowledges::SearchService).to receive(:new) do |hotel:, query:, categories:, **|
        FakeKnowledgeSearch.new(corpus: corpus, query: query, categories: categories)
      end

      # A synthesis step that reaches a real provider is not a unit of anything.
      # Joining the retrieved chunks keeps `reply_matches` meaningful.
      allow_any_instance_of(AiConcierge::Agents::KnowledgeAnswerAgent).to receive(:call) do |agent|
        Array(agent.instance_variable_get(:@matches)).map { |match| match["content"] }.join(" ")
      end
    end

    def install_model_fake(fixture, world)
      stub_concierge_model(
        room_type_names: world[:room_type_names],
        scripted: fixture.turns.to_h { |turn| [ turn.guest, turn.model ] }
      )
    end

    def post_fixture_turn(world, turn)
      before = BookingQuote.count
      result = AiConcierge::Orchestration::Core::InquiryResponder.new(
        hotel: world[:hotel],
        message: turn.guest,
        prospect_public_id: world[:prospect].public_id
      ).call

      TurnResult.new(
        result: result,
        prospect: world[:prospect],
        conversation_state: world[:prospect].prospect_conversation_state.reload,
        quotes_created: BookingQuote.count - before
      )
    end

    def fixture_year_for(month)
      candidate = Date.new(Date.current.year, month, 1)
      candidate < Date.current.beginning_of_month ? Date.current.year + 1 : Date.current.year
    end

    class FakeKnowledgeSearch
      def initialize(corpus:, query:, categories:)
        @corpus = corpus
        @query = query.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
        @categories = Array(categories).map(&:to_s)
      end

      def call
        return [] if @query.blank? || @categories.empty?

        @corpus
          .select { |chunk| @categories.include?(chunk["category"]) }
          .filter_map { |chunk| scored(chunk) }
          .sort_by { |chunk| chunk["distance"] }
          .first(HotelKnowledges::SearchService::DEFAULT_LIMIT)
      end

      private

      # A real embedding that finds the right chunk returns a strong match, so
      # one distinctive word in common has to land under HybridAnswerBuilder's
      # STRONG_MATCH_DISTANCE (0.35). Scoring more timidly than that would send
      # every fixture down the fallback path and quietly test nothing.
      def scored(chunk)
        words = chunk["content"].downcase.gsub(/[^a-z0-9]+/, " ").squish.split
        overlap = (@query.split & words).reject { |word| STOP_WORDS.include?(word) }
        return if overlap.empty?

        chunk.merge("distance" => [ 0.30 - (0.08 * overlap.size), 0.05 ].max)
      end

      STOP_WORDS = %w[
        the a an is are was were do does did i you we what when how any some
        of for in to at on and or my your our there here it its this that
      ].freeze
    end
  end
end

RSpec.configure do |config|
  config.include AiConciergeEval::PipelineDriver, :ai_concierge_eval
end
