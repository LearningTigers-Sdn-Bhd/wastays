# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # The facts that a knowledge turn selected, before they become chat copy.
      #
      # Retrieval owns what is true. ReplyComposer owns how those facts are
      # presented. Keeping the two apart prevents every knowledge tool from
      # inventing a different greeting, empty-state sentence or list style.
      class Reply < Struct.new(
        :shape, :answer_mode, :facts, :remaining_topics, :missing_topic,
        :source, :knowledge_matches, :searched_categories,
        :fallback_categories, :success, keyword_init: true
      )
        SHAPES = %w[direct list unavailable clarification].freeze
        ANSWER_MODES = %w[structured deterministic synthesized fallback unavailable].freeze

        Fact = Struct.new(:topic, :text, :source_refs, keyword_init: true) do
          def initialize(topic: nil, text:, source_refs: [])
            super(topic: topic.to_s.presence, text: text.to_s.strip, source_refs: Array(source_refs))
          end

          def to_h
            { "topic" => topic, "text" => text, "source_refs" => source_refs }
          end

          def self.from_h(value)
            hash = value.respond_to?(:stringify_keys) ? value.stringify_keys : {}
            new(topic: hash["topic"], text: hash["text"], source_refs: hash["source_refs"])
          end
        end

        def initialize(shape:, answer_mode:, facts: [], remaining_topics: [], missing_topic: nil,
                       source: nil, knowledge_matches: [], searched_categories: [],
                       fallback_categories: [], success: true)
          super(
            shape: shape.to_s,
            answer_mode: answer_mode.to_s,
            facts: Array(facts).map { |fact| fact.is_a?(Fact) ? fact : Fact.from_h(fact) }.reject { |fact| fact.text.blank? },
            remaining_topics: Array(remaining_topics).map(&:to_s).compact_blank.uniq,
            missing_topic: missing_topic.to_s.presence,
            source: source,
            knowledge_matches: Array(knowledge_matches),
            searched_categories: Array(searched_categories),
            fallback_categories: Array(fallback_categories),
            success: success
          )
        end

        def to_h
          {
            "shape" => shape,
            "answer_mode" => answer_mode,
            "facts" => facts.map(&:to_h),
            "remaining_topics" => remaining_topics,
            "missing_topic" => missing_topic,
            "source" => source,
            "knowledge_matches" => knowledge_matches,
            "searched_categories" => searched_categories,
            "fallback_categories" => fallback_categories,
            "success" => success
          }
        end

        def self.from_h(value)
          hash = value.respond_to?(:stringify_keys) ? value.stringify_keys : {}
          new(
            shape: hash["shape"],
            answer_mode: hash["answer_mode"],
            facts: hash["facts"],
            remaining_topics: hash["remaining_topics"],
            missing_topic: hash["missing_topic"],
            source: hash["source"],
            knowledge_matches: hash["knowledge_matches"],
            searched_categories: hash["searched_categories"],
            fallback_categories: hash["fallback_categories"],
            success: hash.fetch("success", true)
          )
        end
      end
    end
  end
end
