module AiConcierge
  module MessageBuilders
    class HotelInfoBuilder < BaseBuilder
      def call(reply_type)
        case reply_type.to_sym
        when :hotel_policy
          hotel_policy_message
        when :booking_context
          booking_context_message
        when :general_hotel_info
          general_hotel_info_message
        when :hotel_faq
          hotel_faq_message
        when :nearby_attractions
          nearby_attractions_message
        end
      end

      private

      def hotel_policy_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present?

        facts = []
        facts << knowledge_fact("check-in", "You can check in from #{result['check_in_time']}.") if result["check_in_time"].present?
        facts << knowledge_fact("check-out", "Check-out is by #{result['check_out_time']}.") if result["check_out_time"].present?
        if result["cancellation_policy"].present?
          facts << knowledge_fact("cancellation", "You can cancel under these terms: #{result['cancellation_policy'].to_s.chomp('.')}.")
        end
        facts << knowledge_fact("policy", result["policy_text"]) if facts.empty? && result["policy_text"].present?

        compose_knowledge(shape: facts.one? ? "direct" : "list", facts: facts, missing_topic: "policy information")
      end

      def booking_context_message
        bookings = Array(context[:bookings])
        return "According to our system, we could not find an active booking at the moment." if bookings.empty?

        intro = bookings.one? ? "According to our system, we found your active booking:" : "According to our system, we found your active bookings:"
        lines = bookings.map do |booking|
          dates = [ booking["check_in"], booking["check_out"] ].map { |date| format_date(date) }.join(" - ")
          "- *#{dates}*: #{booking['room_type_name']}"
        end

        [ intro, lines.join("\n") ].join("\n")
      end

      def general_hotel_info_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present?
        summary = result["summary_text"].presence
        amenities = Array(result["amenities"])
        facts = []
        facts << knowledge_fact("hotel information", summary) if summary.present?
        facts << knowledge_fact("amenities", "Available amenities include #{amenities.to_sentence}.") if amenities.present?
        compose_knowledge(shape: facts.many? ? "list" : "direct", facts: facts, missing_topic: "hotel information")
      end

      def hotel_faq_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present?
        facts = result["faq_text"].present? ? [ knowledge_fact("FAQ", result["faq_text"]) ] : []
        compose_knowledge(shape: "direct", facts: facts, missing_topic: "an FAQ answer")
      end

      def nearby_attractions_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present?

        reply = Orchestration::HotelKnowledge::ReplyFactory.new(intent: "nearby_attractions", result: result).call
        Orchestration::HotelKnowledge::ReplyComposer.new(reply: reply, tone: hotel.ai_concierge_tone).call
      end

      def knowledge_fact(topic, text)
        Orchestration::HotelKnowledge::Reply::Fact.new(topic: topic, text: text)
      end

      def compose_knowledge(shape:, facts:, missing_topic:)
        reply = Orchestration::HotelKnowledge::Reply.new(
          shape: facts.empty? ? "unavailable" : shape,
          answer_mode: facts.empty? ? "unavailable" : "fallback",
          facts: facts,
          missing_topic: missing_topic,
          success: facts.present?
        )
        Orchestration::HotelKnowledge::ReplyComposer.new(reply: reply, tone: hotel.ai_concierge_tone).call
      end
    end
  end
end
