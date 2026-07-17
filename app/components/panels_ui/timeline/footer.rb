# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Footer < PanelsUI::BaseComponent
      renders_many :rows, ->(**args) { FooterRow.new(track_count: @track_count, **args) }

      def initialize(track_count:, class: nil, **attributes)
        @track_count = track_count
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline footer requires at least one row" if rows.empty?
      end

      def call
        tag.div(**footer_attributes) do
          safe_join(rows)
        end
      end

      private

      def footer_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__footer", @class, attributes.delete(:class)),
          role: "rowgroup",
          data: data.merge(slot: "timeline-footer")
        )
      end
    end
  end
end
