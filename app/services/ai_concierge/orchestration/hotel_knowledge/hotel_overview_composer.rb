# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # A broad hotel introduction that sells from application-owned facts.
      class HotelOverviewComposer
        MAX_GROUPS = 3
        MAX_AMENITIES_PER_GROUP = 4
        STRUCTURED_TOPICS = [ "star rating", "location", "amenities", "hotel information", "general hotel info" ].freeze
        CATEGORY_LABELS = {
          "Activities" => "Facilities and activities",
          "Services" => "Guest services"
        }.freeze

        def initialize(hotel:, reply:, tone: "basic")
          @hotel = hotel
          @reply = reply
          @tone = tone.to_s
        end

        def call
          [ positioning, distinctive_detail, highlights ].compact_blank.join("\n\n")
        end

        private

        attr_reader :hotel, :reply, :tone

        def positioning
          subject = hotel.name
          subject = "#{subject} is a #{hotel.star_rating}-star hotel" if hotel.star_rating.present?
          subject = "#{subject} in #{concise_location}" if concise_location.present?
          subject = "#{subject}." unless subject.end_with?(".")
          subject
        end

        def concise_location
          [ hotel.city, hotel.country ].compact_blank.uniq.join(", ").presence
        end

        def distinctive_detail
          fact = reply.facts.find do |candidate|
            candidate.source_refs.present? && !structured_topic?(candidate.topic) && useful_detail?(candidate.text)
          end
          fact&.text.to_s.squish.presence
        end

        def structured_topic?(topic)
          STRUCTURED_TOPICS.include?(topic.to_s.downcase.tr("_", " "))
        end

        def useful_detail?(text)
          normalized = text.to_s.downcase
          return false if normalized.blank?
          return false if hotel.address.present? && normalized.include?(hotel.address.downcase)
          return false if normalized.include?(hotel.name.downcase) && normalized.match?(/\b(?:star|located|amenit)/)

          true
        end

        def highlights
          groups = amenity_groups.first(MAX_GROUPS)
          return if groups.empty?

          lines = groups.map do |category, amenities|
            names = amenities.first(MAX_AMENITIES_PER_GROUP).map { |amenity| amenity.fetch(:name) }
            names << "more" if amenities.size > MAX_AMENITIES_PER_GROUP
            "- #{category_label(category)}: #{names.to_sentence}."
          end
          ([ highlights_intro ] + lines).join("\n")
        end

        def amenity_groups
          selected = Array(hotel.amenities)
          Hotel::CATEGORIZED_HOTEL_AMENITIES.filter_map do |group|
            amenities = group.fetch(:items).select { |amenity| selected.include?(amenity.fetch(:id)) }
            [ group.fetch(:category), amenities ] if amenities.present?
          end
        end

        def category_label(category)
          CATEGORY_LABELS.fetch(category, category.to_s.titleize)
        end

        def highlights_intro
          case tone
          when "business" then "Key highlights:"
          when "cheerful" then "A few highlights:"
          else "Highlights include:"
          end
        end
      end
    end
  end
end
