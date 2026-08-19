# frozen_string_literal: true

module PublicUI
  # A short list of actions behind one button.
  #
  # Deliberately not PanelsUI::DropdownMenu. That one carries submenus,
  # selections and a floating-ui positioner for menus that can open anywhere on
  # a dense screen; this one hangs off a fixed corner of the chat bar and holds
  # two items, so it is positioned in CSS and needs none of it. PublicUI is
  # also walled off from PanelsUI on purpose -- a change to the portal's look
  # must not reach a page a guest sees.
  class Menu < PublicUI::BaseComponent
    # One action. A `method` makes it a form, because anything that changes
    # something should not be reachable by following a link.
    class Item < PublicUI::BaseComponent
      def initialize(href:, method: nil, confirm: nil, danger: false, class: nil, **attributes)
        @href = href
        @method = method&.to_sym
        @confirm = confirm
        @danger = danger
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        return link_to(@href, **item_attributes) { content } if @method.blank? || @method == :get

        helpers.button_to(@href, **item_attributes.merge(method: @method, form: { class: "contents" })) { content }
      end

      private

      def item_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        attributes.merge(
          role: "menuitem",
          # Roving tabindex: the menu is one stop on the page, and the arrow
          # keys move within it. Leaving every item tabbable would make a
          # two-item menu two extra stops on the way to the message box.
          tabindex: "-1",
          class: tw_merge("public-menu__item", @class),
          data: data.merge(
            danger: @danger.to_s,
            turbo_confirm: @confirm,
            action: "public-menu#close"
          ).compact
        )
      end
    end

    renders_many :items, Item

    def initialize(label:, icon: "ellipsis-vertical", id: nil, class: nil, **attributes)
      @label = label
      @icon = icon
      @id = id || "public-menu-#{SecureRandom.hex(4)}"
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :label, :icon

    def list_id = "#{@id}-list"

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("public-menu", @class),
        data: data.merge(
          controller: [ data[:controller], "public-menu" ].compact_blank.join(" "),
          action: [ data[:action], "keydown->public-menu#onKeydown", "pointerdown@window->public-menu#onWindowPointerDown" ].compact_blank.join(" ")
        )
      )
    end
  end
end
