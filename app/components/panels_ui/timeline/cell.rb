# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Cell < PanelsUI::BaseComponent
      attr_reader :position

      def initialize(position:, accessible_label:, current: false, class: nil, **attributes)
        @position = Integer(position, exception: false)
        @accessible_label = accessible_label
        @current = ActiveModel::Type::Boolean.new.cast(current)
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline cell position must be a positive integer" unless position&.positive?
        raise ArgumentError, "Timeline cell accessible_label is required" if @accessible_label.blank?
      end

      def call
        tag.div(content, **cell_attributes)
      end

      private

      def cell_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__cell", @class, attributes.delete(:class)),
          role: "cell",
          aria: { label: @accessible_label },
          style: [ "grid-column: #{((position - 1) * 2) + 1} / span 2", attributes.delete(:style) ].compact.join("; "),
          data: data.merge(slot: "timeline-cell", position: position, current: ("true" if @current))
        )
      end
    end
  end
end
