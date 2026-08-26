# frozen_string_literal: true

require "ruby_llm"

module AiConcierge
  module Agents
    class KnowledgeAnswerAgent
      class KnowledgeAnswerError < StandardError; end

      LLM_TIMEOUT = 30

      def initialize(hotel:, message:, intent:, topic:, matches:, structured_facts: {}, scope: "specific")
        @hotel = hotel
        @message = message.to_s.strip
        @intent = intent.to_s
        @topic = topic.to_s
        @matches = Array(matches)
        @structured_facts = structured_facts.to_h
        @scope = scope.to_s
      end

      def call
        response = Timeout.timeout(LLM_TIMEOUT) { chat.ask(prompt) }
        Providers::UsageLog.call(response, hotel: hotel, stage: :knowledge_synthesis)
        parse(response&.content.to_s)
      rescue Timeout::Error
        raise KnowledgeAnswerError, "Knowledge answer request timed out after #{LLM_TIMEOUT}s"
      rescue RubyLLM::Error => e
        raise KnowledgeAnswerError, "Knowledge answer API error: #{e.message}"
      end

      private

      attr_reader :hotel, :message, :intent, :topic, :matches, :structured_facts, :scope

      def chat
        Providers::RubyLlmClient.new(hotel: hotel).chat
      end

      def prompt
        <<~PROMPT
          You are answering a hotel guest question for #{hotel.name}.

          USER QUESTION:
          #{message}

          INTENT: #{intent}
          TOPIC: #{topic}

          HOTEL KNOWLEDGE SNIPPETS:
          #{matches_for_prompt}

          STRUCTURED HOTEL FACTS:
          #{structured_facts.to_json}

          RESPONSE SCOPE: #{scope}

          RULES:
          - Answer only from HOTEL KNOWLEDGE SNIPPETS and STRUCTURED HOTEL FACTS.
          - Do not invent prices, times, availability, amenities, exceptions, or policies.
          - Return facts, not a greeting, sign-off or offer of further help.
          - Keep each fact to one short guest-facing sentence.
          - For a specific question, return no more than two facts.
          - For a broad question, return no more than ten facts.
          - Do not mention sources, documents, snippets, internal metadata, or citations.

          Reply with JSON only:
          {"facts":[{"topic":"short topic name","text":"supported fact","source_refs":[1]}]}

          source_refs contains the one-based numbers of the snippets that support the fact.
          Do not return a fact without at least one valid source_refs number.
        PROMPT
      end

      def parse(content)
        json = content[/\{.*\}/m]
        raise KnowledgeAnswerError, "Knowledge answer returned no JSON" if json.blank?

        parsed = JSON.parse(json)
        limit = scope == "broad" ? 10 : 2
        facts = Array(parsed["facts"]).filter_map { |fact| supported_fact(fact) }.first(limit)
        raise KnowledgeAnswerError, "Knowledge answer returned no supported facts" if facts.empty?

        facts
      rescue JSON::ParserError => e
        raise KnowledgeAnswerError, "Knowledge answer returned malformed JSON: #{e.message}"
      end

      def supported_fact(value)
        fact = value.respond_to?(:stringify_keys) ? value.stringify_keys : {}
        text = fact["text"].to_s.strip
        refs = Array(fact["source_refs"]).filter_map { |item| Integer(item, exception: false) }.uniq
        return if text.blank? || refs.empty?
        return unless refs.all? { |index| index.between?(1, matches.size) }

        Orchestration::HotelKnowledge::Reply::Fact.new(
          topic: fact["topic"],
          text: text,
          source_refs: refs
        )
      end

      def matches_for_prompt
        return "None." if matches.empty?

        matches.each_with_index.map do |match, index|
          title = match["document_title"].presence || "Untitled"
          category = match["category"].presence || "knowledge"
          "#{index + 1}. [#{category} / #{title}] #{match['content']}"
        end.join("\n")
      end
    end
  end
end
