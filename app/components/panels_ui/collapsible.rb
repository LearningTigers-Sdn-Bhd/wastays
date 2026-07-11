# frozen_string_literal: true

module PanelsUI
  # A headless disclosure primitive modelled after shadcn/Radix Collapsible.
  # The server owns the initial state and accessible relationships; a scoped
  # Stimulus controller owns subsequent state changes and height animation.
  #
  #   <%= render PanelsUI::Collapsible.new(id: "booking-details") do |item| %>
  #     <% item.with_trigger { "Booking details" } %>
  #     <% item.with_body { render "bookings/details" } %>
  #   <% end %>
  #
  # The component intentionally does not insert an icon or card styling. Callers
  # can add an element with `.panel-collapsible__indicator`; the supplied CSS
  # rotates it from the root's `data-state`.
  class Collapsible < PanelsUI::BaseComponent
    renders_one :trigger
    renders_one :body

    style base: "panel-collapsible"

    def initialize(id: nil, open: false, disabled: false, class: nil,
                   trigger_class: nil, content_class: nil, **attributes)
      @id = id.presence || "collapsible-#{object_id}"
      @open = ActiveModel::Type::Boolean.new.cast(open)
      @disabled = ActiveModel::Type::Boolean.new.cast(disabled)
      @class = binding.local_variable_get(:class)
      @trigger_class = trigger_class
      @content_class = content_class
      @attributes = attributes
    end

    attr_reader :id

    def before_render
      raise ArgumentError, "Collapsible requires a trigger slot" unless trigger?
      raise ArgumentError, "Collapsible requires a body slot" unless body?
    end

    def open? = @open
    def disabled? = @disabled
    def state = open? ? "open" : "closed"
    def trigger_id = "#{id}-trigger"
    def content_id = "#{id}-content"

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || attributes.delete("data") || {}

      attributes.merge(
        id: id,
        class: class_for(class_override: @class),
        data: data.merge(
          controller: controller_names(data),
          state: state,
          disabled: ("" if disabled?),
          panels_ui__collapsible_open_value: open?,
          panels_ui__collapsible_disabled_value: disabled?
        ).compact
      )
    end

    def trigger_attributes
      {
        id: trigger_id,
        type: "button",
        class: tw_merge("panel-collapsible__trigger", @trigger_class),
        disabled: disabled?,
        aria: { expanded: open?.to_s, controls: content_id },
        data: {
          state: state,
          disabled: ("" if disabled?),
          panels_ui__collapsible_target: "trigger",
          action: "click->panels-ui--collapsible#toggle"
        }.compact
      }
    end

    def content_attributes
      {
        id: content_id,
        class: tw_merge("panel-collapsible__content", @content_class),
        hidden: !open?,
        inert: (!open? ? "" : nil),
        data: {
          state: state,
          disabled: ("" if disabled?),
          panels_ui__collapsible_target: "content"
        }.compact
      }
    end

    private

    def controller_names(data)
      caller_controller = data.delete(:controller) || data.delete("controller")
      [ caller_controller, "panels-ui--collapsible" ].compact.join(" ")
    end
  end
end
