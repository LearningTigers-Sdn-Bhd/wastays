# frozen_string_literal: true

module HotelKnowledges
  class DiagnosticRecorder
    WEAK_MATCH_DISTANCE = 0.55
    KNOWLEDGE_INTENTS = %w[hotel_policy hotel_information nearby_attractions room_information].freeze

    def initialize(hotel:, question:, intent:, topic:, tool_result:, prospect: nil, prospect_message: nil, source: "ai_concierge")
      @hotel = hotel
      @question = question.to_s.strip
      @intent = intent.to_s
      @topic = topic.to_s
      @tool_result = tool_result.is_a?(Hash) ? tool_result : {}
      @prospect = prospect
      @prospect_message = prospect_message
      @source = source
    end

    def call
      return unless recordable?

      hotel.knowledge_diagnostics.create!(
        prospect: prospect,
        prospect_message: prospect_message || latest_inbound_message,
        question: question,
        intent: intent,
        topic: topic.presence,
        routed_categories: routed_categories,
        fallback_categories: fallback_categories,
        answer_mode: answer_mode,
        answer: answer,
        success: success?,
        source: tool_result["source"].presence || source,
        knowledge_matches: knowledge_matches,
        match_count: knowledge_matches.count,
        best_distance: best_distance,
        suggested_category: suggested_category,
        metadata: metadata
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("HotelKnowledges::DiagnosticRecorder skipped invalid diagnostic: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("HotelKnowledges::DiagnosticRecorder failed: #{e.class}: #{e.message}")
      nil
    end

    private

    attr_reader :hotel, :question, :intent, :topic, :tool_result, :prospect, :prospect_message, :source

    def recordable?
      hotel.present? &&
        question.present? &&
        KNOWLEDGE_INTENTS.include?(intent) &&
        diagnostic_worthy?
    end

    def diagnostic_worthy?
      return true unless success?
      return true if answer_mode == "unavailable"
      return true if answer_mode == "fallback" && knowledge_matches.empty?
      return true if knowledge_matches.empty? && !structured_room_or_attractions_result?
      return true if best_distance.blank? && knowledge_matches.present?
      return true if best_distance.to_f > WEAK_MATCH_DISTANCE

      false
    end

    def structured_room_or_attractions_result?
      intent == "nearby_attractions" || (intent == "room_information" && tool_result["matched_room_type_id"].present?)
    end

    def success?
      ActiveModel::Type::Boolean.new.cast(tool_result.fetch("success", false))
    end

    def answer_mode
      tool_result["answer_mode"].presence || inferred_answer_mode
    end

    def inferred_answer_mode
      return "unavailable" unless success?
      return "structured" if structured_room_or_attractions_result?

      "fallback"
    end

    def answer
      tool_result["answer"].presence || tool_result["policy_text"].presence || tool_result["faq_text"].presence || tool_result["summary_text"].presence
    end

    def knowledge_matches
      Array(tool_result["knowledge_matches"]).select { |match| match.is_a?(Hash) }
    end

    def best_distance
      values = knowledge_matches.filter_map { |match| match["distance"] }
      return if values.empty?

      values.map { |value| BigDecimal(value.to_s) }.min
    rescue ArgumentError
      nil
    end

    def routed_categories
      Array(tool_result["searched_categories"]).presence || Array(category_for_intent).compact
    end

    def fallback_categories
      Array(tool_result["fallback_categories"])
    end

    def suggested_category
      case topic.presence || intent
      when "hotel_policy"
        "policy"
      when "hotel_faq"
        "faq"
      when "hotel_information", "general_hotel_info"
        "general_info"
      end
    end

    def category_for_intent
      case intent
      when "hotel_policy"
        "policy"
      when "hotel_information"
        topic == "hotel_faq" ? "faq" : "general_info"
      end
    end

    def latest_inbound_message
      return unless prospect

      prospect.prospect_messages.where(direction: "inbound").order(sent_at: :desc, created_at: :desc).first
    end

    def metadata
      {
        "producer" => source,
        "tool_source" => tool_result["source"],
        "matched_room_type_id" => tool_result["matched_room_type_id"],
        "room_type_name" => tool_result["room_type_name"],
        "error" => tool_result["error"]
      }.compact
    end
  end
end
