# frozen_string_literal: true

module PanelsUI
  class AvatarGroup < PanelsUI::BaseComponent
    class Count < PanelsUI::BaseComponent
      def initialize(count:, label: nil, size: :default, class: nil, **attributes)
        @count = count.to_i
        @label = label
        @size = size
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Avatar group count must be positive" unless @count.positive?
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}
        aria[:label] ||= @label.presence || "#{@count} more"

        tag.span(
          "+#{@count}",
          **attributes.merge(
            class: tw_merge("panel-avatar-group__count", @class),
            role: attributes.delete(:role) || "img",
            aria: aria,
            data: data.merge(slot: "avatar-group-count", size: @size)
          )
        )
      end
    end

    SIZES = PanelsUI::Avatar::SIZES
    VARIANTS = %i[compact loose].freeze

    renders_many :avatars, ->(**args) { PanelsUI::Avatar.new(**args.merge(size: @size)) }
    renders_one :count, ->(**args) { Count.new(**args.merge(size: @size)) }

    def initialize(aria_label:, size: :default, variant: :compact, class: nil, **attributes)
      @aria_label = aria_label
      @size = SIZES.include?(size) ? size : :default
      @variant = VARIANTS.include?(variant) ? variant : :compact
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      raise ArgumentError, "Avatar group aria_label is required" if @aria_label.blank?
      raise ArgumentError, "Avatar group requires an avatar or count" unless avatars.any? || count?
    end

    def call
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @aria_label

      tag.div(
        safe_join([ *avatars, (count if count?) ].compact),
        **attributes.merge(
          class: tw_merge("panel-avatar-group", @class),
          role: attributes.delete(:role) || "group",
          aria: aria,
          data: data.merge(slot: "avatar-group", size: @size, variant: @variant)
        )
      )
    end
  end
end
