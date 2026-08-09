# frozen_string_literal: true

module PanelsUI
  # A compound accordion that coordinates PanelsUI::Collapsible items while
  # retaining native headings and button semantics.
  class Accordion < PanelsUI::BaseComponent
    VARIANTS = %i[default bordered].freeze
    TYPES = %i[single multiple].freeze

    class Item < PanelsUI::BaseComponent
      renders_one :trigger
      renders_one :body
      renders_one :header_content

      attr_reader :value

      def initialize(accordion:, value:, disabled: false, region: false, id: nil,
                     class: nil, trigger_class: nil, content_class: nil,
                     header_class: nil, **attributes)
        @accordion = accordion
        @value = value.to_s
        @disabled = ActiveModel::Type::Boolean.new.cast(disabled)
        @region = ActiveModel::Type::Boolean.new.cast(region)
        @id = id
        @class = binding.local_variable_get(:class)
        @trigger_class = trigger_class
        @content_class = content_class
        @header_class = header_class
        @attributes = attributes
        @open = false
        @locked_open = false
      end

      def before_render
        raise ArgumentError, "Accordion item requires a trigger slot" unless trigger?
        raise ArgumentError, "Accordion item requires a body slot" unless body?
      end

      def disabled? = @disabled

      def configure(index:, open:, locked_open:)
        @id ||= "#{@accordion.id}-item-#{index + 1}"
        @open = open
        @locked_open = locked_open
      end

      def call
        # Materialize the slot in this component's view context before passing
        # it through to the nested Collapsible component.
        body_content = body.to_s
        header_content_value = header_content.to_s if header_content?
        attributes = @attributes.deep_dup
        caller_data = attributes.delete(:data) || attributes.delete("data") || {}

        render PanelsUI::Collapsible.new(
          id: @id,
          open: @open,
          disabled: disabled?,
          heading_level: @accordion.heading_level,
          region: @region,
          class: tw_merge("panel-accordion__item", @class),
          trigger_class: tw_merge("panel-accordion__trigger", @trigger_class),
          content_class: tw_merge("panel-accordion__content", @content_class),
          header_class: @header_class,
          trigger_attributes: {
            aria: { disabled: ("true" if @locked_open) },
            data: { accordion_trigger: "" }
          },
          **attributes,
          data: caller_data.merge(accordion_item: "", accordion_value: value)
        ) do |collapsible|
          collapsible.with_trigger do
            safe_join([
              tag.span(trigger, class: "panel-accordion__label"),
              helpers.app_icon("chevron-down", class: "panel-accordion__indicator", aria: { hidden: "true" })
            ])
          end
          collapsible.with_header_content { header_content_value } if header_content_value
          collapsible.with_body { body_content }
        end
      end
    end

    renders_many :items, ->(value:, **attributes) {
      Item.new(accordion: self, value: value, **attributes)
    }

    style base: "panel-accordion",
          variants: {
            variant: {
              default: "panel-accordion--default",
              bordered: "panel-accordion--bordered"
            }
          },
          defaults: { variant: :default }

    attr_reader :id, :heading_level

    def initialize(id: nil, variant: :default, type: :single, collapsible: false,
                   default_open: [], heading_level:, class: nil, **attributes)
      @id = id.presence || "accordion-#{object_id}"
      @variant = variant.to_sym
      @type = type.to_sym
      @collapsible = ActiveModel::Type::Boolean.new.cast(collapsible)
      @default_open = Array(default_open).map(&:to_s)
      @heading_level = heading_level
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      validate!
      configure_items!
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || attributes.delete("data") || {}
      caller_controller = data.delete(:controller) || data.delete("controller")
      caller_action = data.delete(:action) || data.delete("action")

      attributes.merge(
        id: id,
        class: class_for(variant: @variant, class_override: tw_merge(@class, attributes.delete(:class))),
        data: data.merge(
          slot: "accordion",
          variant: @variant,
          controller: [ caller_controller, "panels-ui--accordion" ].compact.join(" "),
          action: [
            caller_action,
            "keydown->panels-ui--accordion#navigate",
            "panels-ui--collapsible:change->panels-ui--accordion#itemChanged"
          ].compact.join(" "),
          panels_ui__accordion_type_value: @type,
          panels_ui__accordion_collapsible_value: @collapsible
        )
      )
    end

    private

    def validate!
      raise ArgumentError, "Accordion requires at least one item" if items.empty?
      raise ArgumentError, "Accordion variant must be one of: #{VARIANTS.join(', ')}" unless VARIANTS.include?(@variant)
      raise ArgumentError, "Accordion type must be one of: #{TYPES.join(', ')}" unless TYPES.include?(@type)
      unless @heading_level.is_a?(Integer) && (2..6).cover?(@heading_level)
        raise ArgumentError, "Accordion heading_level must be between 2 and 6"
      end
      raise ArgumentError, "Accordion multiple type does not accept collapsible" if @type == :multiple && @collapsible
      raise ArgumentError, "Accordion item values must be present" if items.any? { |item| item.value.blank? }
      raise ArgumentError, "Accordion item values must be unique" if items.map(&:value).uniq.length != items.length
      raise ArgumentError, "Accordion default_open values must be unique" if @default_open.uniq.length != @default_open.length
      raise ArgumentError, "Accordion single type accepts at most one default_open value" if @type == :single && @default_open.many?

      unknown = @default_open - items.map(&:value)
      raise ArgumentError, "Accordion default_open contains unknown values: #{unknown.join(', ')}" if unknown.any?

      disabled = items.select { |item| item.disabled? && @default_open.include?(item.value) }.map(&:value)
      raise ArgumentError, "Accordion default_open cannot include disabled items: #{disabled.join(', ')}" if disabled.any?
    end

    def configure_items!
      if @type == :single && !@collapsible && @default_open.empty?
        first_enabled = items.find { |item| !item.disabled? }
        raise ArgumentError, "Accordion non-collapsible single type requires an enabled item" unless first_enabled

        @default_open = [ first_enabled.value ]
      end

      items.each_with_index do |item, index|
        open = @default_open.include?(item.value)
        item.configure(index: index, open: open, locked_open: @type == :single && !@collapsible && open)
      end
    end
  end
end
