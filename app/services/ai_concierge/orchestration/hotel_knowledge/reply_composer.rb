# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # One voice for policy, FAQ, hotel, attraction and room information.
      class ReplyComposer
        MAX_DIRECT_SENTENCES = 2
        MAX_LIST_FACTS = 5

        FILLER_SENTENCES = [
          /\Athank you for (?:your|the) (?:question|inquiry)[!.]?\s*/i,
          /\s*please let us know if .+?[!.]?\z/i,
          /\s*we(?:'re| are) (?:always )?happy to help[!.]?\z/i,
          /\s*feel free to (?:ask|contact) .+?[!.]?\z/i
        ].freeze

        def initialize(reply:, tone: "basic", message: nil, previous_reply: nil)
          @reply = reply
          @tone = tone.to_s
          @message = message.to_s
          @previous_reply = previous_reply.to_s
        end

        def call
          case reply.shape
          when "list" then list_message
          when "unavailable" then unavailable_message
          when "clarification" then clarification_message
          else direct_message
          end
        end

        private

        attr_reader :reply, :tone, :message, :previous_reply

        def direct_message
          sentences = eligible_facts.flat_map { |fact| sentences_in(clean(fact.text)) }
          sentences.first(MAX_DIRECT_SENTENCES).join(" ").presence || empty_facts_message
        end

        def list_message
          visible = eligible_facts.first(MAX_LIST_FACTS)
          return empty_facts_message if visible.empty?

          lines = [ list_intro ] + visible.map { |fact| "- #{clean(fact.text)}" }
          topics = reply.remaining_topics.compact_blank.uniq
          lines << "Other available topics include #{join_topics(topics)}." if topics.any?
          lines.join("\n")
        end

        def unavailable_message
          topic = reply.missing_topic.presence || "that information"

          case topic
          when "nearby attractions"
            "The hotel has not listed nearby attractions yet."
          when "room type"
            "I could not match that room type. Please send the room type name."
          when "room type choice"
            reply.facts.first&.text.presence || "Please tell me which room type you mean."
          when "service information"
            "The hotel has not listed that service yet."
          when "an FAQ answer"
            "I could not find that answer in the hotel's FAQ."
          when "policy information"
            "The hotel has not added that policy yet."
          else
            "The hotel has not added #{topic} yet."
          end
        end

        def clarification_message
          reply.facts.first&.text.presence || "Please tell me which topic you mean."
        end

        def empty_facts_message
          return unavailable_message unless follow_up?
          return "I could not find another listed restriction." if message.match?(/\b(?:restrict|rule|polic)/i)
          return "I could not find another listed amenity or service." if message.match?(/\b(?:amenit|facilit|service)/i)

          "I could not find another listed detail."
        end

        def eligible_facts
          return reply.facts unless follow_up? && previous_reply.present?

          reply.facts.reject { |fact| already_said?(fact) }
        end

        def follow_up?
          message.match?(/\b(?:else|another|other|anything more)\b/i)
        end

        def already_said?(fact)
          previous = normalized(previous_reply)
          text = normalized(fact.text)
          topic = normalized(fact.topic)

          previous.include?(text) || (specific_topic?(topic) && previous.include?(topic))
        end

        def normalized(value)
          value.to_s.downcase.gsub(/[^\p{Alnum}\s]/, " ").squish
        end

        def specific_topic?(topic)
          topic.length >= 4 && !%w[faq policy details information rules].include?(topic)
        end

        def list_intro
          case tone
          when "business" then "The available details are:"
          when "cheerful" then "Here are the details we have:"
          else "Here are the available details:"
          end
        end

        def clean(text)
          cleaned = text.to_s.squish
          FILLER_SENTENCES.each { |pattern| cleaned = cleaned.sub(pattern, "") }
          cleaned = business_wording(cleaned) if tone == "business"
          cleaned.strip
        end

        def business_wording(text)
          text
            .gsub(/\b[Cc]an't\b/, "cannot")
            .gsub(/\b[Ww]on't\b/, "will not")
            .gsub(/\b[Dd]on't\b/, "do not")
            .gsub(/\b[Ii]t's\b/, "it is")
            .gsub(/\b[Ww]e're\b/, "we are")
            .tr("!", ".")
        end

        def sentences_in(text)
          text.to_s.scan(/.+?(?:[.!?](?=\s|\z)|\z)/).map(&:strip).reject(&:blank?)
        end

        def join_topics(topics)
          return topics.first if topics.one?

          "#{topics[0...-1].join(', ')} or #{topics.last}"
        end
      end
    end
  end
end
