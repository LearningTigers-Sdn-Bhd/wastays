# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Table < PanelsUI::BaseComponent
      DENSITIES = %i[compact comfortable].freeze

      renders_one :header, ->(**args) { Header.new(track_count: @track_count, **args) }
      renders_many :groups, ->(**args) { Group.new(track_count: @track_count, **args) }
      renders_one :footer, ->(**args) { Footer.new(track_count: @track_count, **args) }

      style base: "panel-timeline"

      attr_reader :caption, :track_count

      def initialize(caption:, track_count:, density: :compact, class: nil, **attributes)
        @caption = caption
        @track_count = Integer(track_count, exception: false)
        @density = density.to_sym
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline caption is required" if caption.blank?
        unless track_count&.positive? && track_count.even?
          raise ArgumentError, "Timeline track_count must be a positive even integer"
        end
        unless DENSITIES.include?(@density)
          raise ArgumentError, "Timeline density must be one of: #{DENSITIES.join(', ')}"
        end
        raise ArgumentError, "Timeline header slot is required" unless header?
      end

      def day_count = track_count / 2
      def hint_id = "#{dom_id}-scroll-hint"
      def dom_id = @attributes[:id].presence || "timeline-#{caption.to_s.parameterize.presence || 'view'}"

      def root_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}
        aria = attributes.delete(:aria) || attributes.delete("aria") || {}

        attributes.merge(
          id: dom_id,
          role: "table",
          tabindex: 0,
          class: class_for(class_override: @class),
          style: timeline_style(attributes.delete(:style)),
          aria: aria.merge(label: caption, describedby: hint_id),
          data: data.merge(slot: "timeline", density: @density, track_count: track_count)
        )
      end

      private

      def timeline_style(caller_style)
        [ "--panel-timeline-track-count: #{track_count}", caller_style ].compact.join("; ")
      end
    end
  end
end
