# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Segment < PanelsUI::BaseComponent
      TONES = %i[neutral primary info success warning destructive].freeze
      EMPHASES = %i[solid subtle hatched].freeze

      attr_reader :start_track, :end_track

      def initialize(start_track:, end_track:, accessible_label:, tone: :neutral, emphasis: :solid,
                     clipped_left: false, clipped_right: false, href: nil, class: nil,
                     link_attributes: {}, **attributes)
        @start_track = Integer(start_track, exception: false)
        @end_track = Integer(end_track, exception: false)
        @accessible_label = accessible_label
        @tone = tone.to_sym
        @emphasis = emphasis.to_sym
        @clipped_left = ActiveModel::Type::Boolean.new.cast(clipped_left)
        @clipped_right = ActiveModel::Type::Boolean.new.cast(clipped_right)
        @href = href
        @class = binding.local_variable_get(:class)
        @link_attributes = link_attributes
        @attributes = attributes
      end

      def before_render
        unless start_track&.positive? && end_track&.positive? && end_track > start_track
          raise ArgumentError, "Timeline segment tracks must define a positive increasing range"
        end
        raise ArgumentError, "Timeline segment accessible_label is required" if @accessible_label.blank?
        raise ArgumentError, "Timeline segment tone must be one of: #{TONES.join(', ')}" unless TONES.include?(@tone)
        unless EMPHASES.include?(@emphasis)
          raise ArgumentError, "Timeline segment emphasis must be one of: #{EMPHASES.join(', ')}"
        end
      end

      def call
        tag.div(**segment_attributes) do
          @href.present? ? segment_link : static_segment
        end
      end

      private

      def segment_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__segment", @class, attributes.delete(:class)),
          style: [ "grid-column: #{start_track} / #{end_track}", attributes.delete(:style) ].compact.join("; "),
          data: data.merge(
            slot: "timeline-segment",
            tone: @tone,
            emphasis: @emphasis,
            clipped_left: @clipped_left.to_s,
            clipped_right: @clipped_right.to_s
          )
        )
      end

      def segment_link
        attributes = @link_attributes.deep_dup
        aria = attributes.delete(:aria) || attributes.delete("aria") || {}

        helpers.link_to(
          @href,
          **attributes.merge(
            class: tw_merge("panel-timeline__segment-content panel-timeline__segment-action", attributes.delete(:class)),
            aria: aria.merge(label: @accessible_label)
          )
        ) { content }
      end

      def static_segment
        tag.span(
          content,
          class: "panel-timeline__segment-content",
          role: "img",
          aria: { label: @accessible_label }
        )
      end
    end
  end
end
