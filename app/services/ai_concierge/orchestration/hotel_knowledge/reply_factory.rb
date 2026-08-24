# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # Adapts every knowledge tool to the same semantic reply contract.
      class ReplyFactory
        def initialize(intent:, result:)
          @intent = intent.to_s
          @result = result
        end

        def call
          case intent
          when "nearby_attractions" then attraction_reply
          when "room_information" then room_reply
          else Reply.from_h(result)
          end
        end

        private

        attr_reader :intent, :result

        def attraction_reply
          attractions = Array(result["attractions"])
          return unavailable("nearby attractions") if attractions.empty?

          Reply.new(
            shape: "list",
            answer_mode: "structured",
            facts: attractions.map { |attraction| attraction_fact(attraction) },
            source: "nearby_attractions",
            success: true
          )
        end

        def attraction_fact(attraction)
          details = [
            attraction["description"],
            attraction["address"],
            attraction["city"],
            attraction["country"],
            distance_text(attraction["distance_km"])
          ].compact_blank.join(". ")
          text = details.present? ? "#{attraction['name']}: #{details}." : "#{attraction['name']}."

          Reply::Fact.new(topic: attraction["name"], text: text)
        end

        def room_reply
          return room_details_reply if result["success"]

          if result["error"] == "ambiguous_room_type"
            names = Array(result["room_type_names"])
            return Reply.new(
              shape: "clarification",
              answer_mode: "structured",
              facts: [ Reply::Fact.new(text: "I found several matching room types: #{join_names(names)}. Which one do you mean?") ],
              source: "room_information",
              success: false
            )
          end

          unavailable("room type")
        end

        def room_details_reply
          details = []
          details << "#{result['room_type_name']}: #{sentence(result['description'])}" if result["description"].present?

          occupancy = occupancy_text
          amenities = Array(result["amenities"])
          second = [ occupancy, amenities.presence && "amenities include #{amenities.join(', ')}" ].compact.join("; ")
          details << sentence(second) if second.present?
          details << "Here are the details for #{result['room_type_name']}." if details.empty?

          Reply.new(
            shape: "direct",
            answer_mode: "structured",
            facts: details.map { |text| Reply::Fact.new(topic: result["room_type_name"], text: text) },
            source: "room_information",
            success: true
          )
        end

        def occupancy_text
          parts = []
          adults = result["max_adults"]
          children = result["max_children"]
          parts << "#{adults} #{'adult'.pluralize(adults)}" if adults.present?
          parts << "#{children} #{'child'.pluralize(children)}" if children.present?
          return if parts.empty?

          "The room accommodates #{parts.to_sentence}"
        end

        def unavailable(topic)
          Reply.new(
            shape: "unavailable",
            answer_mode: "unavailable",
            missing_topic: topic,
            source: intent,
            success: false
          )
        end

        def distance_text(distance)
          "About #{format('%.1f', distance)} km away in a straight line" if distance.present?
        end

        def sentence(text)
          value = text.to_s.strip
          value.match?(/[.!?]\z/) ? value : "#{value}."
        end

        def join_names(names)
          names.to_sentence
        end
      end
    end
  end
end
