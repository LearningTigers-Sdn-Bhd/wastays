# frozen_string_literal: true

module PanelsUI
  class DropdownMenu < PanelsUI::BaseComponent
    PLACEMENTS = %i[
      top top_start top_end right right_start right_end
      bottom bottom_start bottom_end left left_start left_end
    ].freeze
    VARIANTS = %i[default primary info success warning danger].freeze

    class Entry < PanelsUI::BaseComponent
      def initialize(href: nil, method: nil, form: {}, variant: :default, disabled: false, class: nil, **attributes)
        @href = href
        @method = method&.to_sym
        @form = form
        @variant = VARIANTS.include?(variant) ? variant : :default
        @disabled = disabled
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        return method_button if method_button?

        tag.public_send(tag_name, content, **item_attributes)
      end

      private

      def method_button?
        @href.present? && @method.present? && @method != :get
      end

      def method_button
        helpers.button_to(
          @href,
          **item_attributes.merge(
            method: @method,
            form: { class: "contents" }.merge(@form)
          )
        ) { content }
      end

      def tag_name = @href.present? ? :a : :button

      def item_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}
        attributes.merge(
          href: (method_button? ? nil : @href),
          type: (@href.present? ? nil : "button"),
          role: "menuitem",
          tabindex: "-1",
          class: tw_merge("dropdown-menu__item", @class),
          data: data.merge(
            variant: @variant,
            panels_ui__dropdown_menu_target: "item",
            dropdown_menu_kind: "command"
          ),
          aria: aria.merge(disabled: (@disabled ? "true" : nil))
        ).compact
      end
    end

    class Selection < PanelsUI::BaseComponent
      def initialize(type:, name:, value:, checked: false, disabled: false, variant: :default, class: nil)
        @type = type
        @name = name
        @value = value
        @checked = checked
        @disabled = disabled
        @variant = VARIANTS.include?(variant) ? variant : :default
        @class = binding.local_variable_get(:class)
      end

      def call
        tag.button(
          safe_join([ indicator, tag.span(content, class: "dropdown-menu__item-label"), input ]),
          type: "button",
          role: "menuitem#{@type}",
          tabindex: "-1",
          class: tw_merge("dropdown-menu__item dropdown-menu__selection", @class),
          data: {
            variant: @variant,
            panels_ui__dropdown_menu_target: "item",
            dropdown_menu_kind: @type
          },
          aria: { checked: @checked.to_s, disabled: (@disabled ? "true" : nil) }.compact
        )
      end

      private

      def indicator
        tag.span("", class: "dropdown-menu__indicator", aria: { hidden: "true" }, data: { selection_type: @type })
      end

      def input
        tag.input(
          type: @type,
          name: @name,
          value: @value,
          checked: @checked,
          hidden: true,
          tabindex: "-1",
          aria: { hidden: "true" },
          data: { panels_ui__dropdown_menu_target: "selectionInput" }
        )
      end
    end

    class Checkbox < Selection
      def initialize(**args)
        super(type: :checkbox, **args)
      end
    end

    class RadioOption < Selection
      def initialize(name:, **args)
        super(type: :radio, name: name, **args)
      end
    end

    class RadioGroup < PanelsUI::BaseComponent
      renders_many :options, lambda { |**args|
        RadioOption.new(name: @name, **args)
      }

      def initialize(name:, label:)
        @name = name
        @label = label
      end

      def call
        tag.div(
          safe_join([ tag.div(@label, class: "dropdown-menu__group-label", aria: { hidden: "true" }), safe_join(options) ]),
          role: "group",
          aria: { label: @label },
          class: "dropdown-menu__group"
        )
      end
    end

    class Separator < PanelsUI::BaseComponent
      def call
        tag.div("", role: "separator", aria: { orientation: "horizontal" }, class: "dropdown-menu__separator")
      end
    end

    module EntrySlots
      extend ActiveSupport::Concern

      included do
        renders_many :entries, types: {
          item: Entry,
          checkbox: Checkbox,
          radio_group: RadioGroup,
          group: ->(**args) { Group.new(**args) },
          separator: Separator
        }
      end
      def with_item(...) = with_entry_item(...)
      def with_checkbox(...) = with_entry_checkbox(...)
      def with_radio_group(...) = with_entry_radio_group(...)
      def with_group(...) = with_entry_group(...)
      def with_separator(...) = with_entry_separator(...)
    end

    class Group < PanelsUI::BaseComponent
      include EntrySlots

      def initialize(label:)
        @label = label
      end

      def call
        tag.div(
          safe_join([ tag.div(@label, class: "dropdown-menu__group-label", aria: { hidden: "true" }), safe_join(entries) ]),
          role: "group",
          aria: { label: @label },
          class: "dropdown-menu__group"
        )
      end
    end

    class Submenu < PanelsUI::BaseComponent
      include EntrySlots

      def initialize(label:, id: nil, disabled: false, variant: :default, class: nil)
        @label = label
        @id = id || "dropdown-submenu-#{object_id}"
        @disabled = disabled
        @variant = VARIANTS.include?(variant) ? variant : :default
        @class = binding.local_variable_get(:class)
      end

      def call
        tag.div(safe_join([ trigger, panel ]), class: "dropdown-menu__submenu", data: {
          action: "pointerleave->panels-ui--dropdown-menu#scheduleSubmenuClose"
        })
      end

      private

      def trigger
        tag.button(
          safe_join([
            tag.span(@label, class: "dropdown-menu__item-label"),
            tag.span("›", class: "dropdown-menu__submenu-arrow", aria: { hidden: "true" })
          ]),
          type: "button",
          role: "menuitem",
          tabindex: "-1",
          class: "dropdown-menu__item",
          data: {
            variant: @variant,
            panels_ui__dropdown_menu_target: "item submenuTrigger",
            dropdown_menu_kind: "submenu",
            action: "pointerenter->panels-ui--dropdown-menu#openSubmenuFromPointer"
          },
          aria: {
            haspopup: "menu",
            expanded: "false",
            controls: @id,
            disabled: (@disabled ? "true" : nil)
          }.compact
        )
      end

      def panel
        tag.div(
          safe_join(entries),
          id: @id,
          role: "menu",
          tabindex: "-1",
          popover: "manual",
          class: tw_merge("dropdown-menu dropdown-menu--submenu", @class),
          data: {
            panels_ui__dropdown_menu_target: "submenuPanel",
            action: "pointerenter->panels-ui--dropdown-menu#cancelSubmenuClose"
          },
          aria: { label: @label }
        )
      end
    end

    class Trigger < PanelsUI::BaseComponent
      def initialize(id:, menu_id:, variant: :primary, size: :md, aria_label: nil, class: nil, **attributes)
        @id = id
        @menu_id = menu_id
        @variant = Button::VARIANTS.include?(variant) ? variant : :primary
        @size = Button::SIZES.include?(size) ? size : :md
        @aria_label = aria_label
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}

        tag.button(
          content,
          **attributes.merge(
            id: @id,
            type: "button",
            class: tw_merge("panel-button dropdown-menu__trigger", @class),
            data: data.merge(
              variant: @variant,
              size: @size,
              panels_ui__dropdown_menu_target: "trigger",
              action: "click->panels-ui--dropdown-menu#toggle keydown->panels-ui--dropdown-menu#onTriggerKeydown"
            ),
            aria: aria.merge(
              label: @aria_label,
              haspopup: "menu",
              expanded: "false",
              controls: @menu_id
            ).compact
          )
        )
      end
    end

    renders_one :trigger, lambda { |**args|
      Trigger.new(id: trigger_id, menu_id: menu_id, **args)
    }

    renders_one :header

    renders_many :entries, types: {
      item: Entry,
      checkbox: Checkbox,
      radio_group: RadioGroup,
      group: Group,
      separator: Separator,
      submenu: Submenu
    }

    def initialize(id:, placement: :bottom_start, offset: 6, class: nil)
      @id = id
      @placement = PLACEMENTS.include?(placement) ? placement : :bottom_start
      @offset = offset.to_f
      @class = binding.local_variable_get(:class)
    end

    def with_item(...) = with_entry_item(...)
    def with_checkbox(...) = with_entry_checkbox(...)
    def with_radio_group(...) = with_entry_radio_group(...)
    def with_group(...) = with_entry_group(...)
    def with_separator(...) = with_entry_separator(...)
    def with_submenu(...) = with_entry_submenu(...)

    def trigger_id = "#{@id}-trigger"
    def menu_id = "#{@id}-menu"
    def floating_placement = @placement.to_s.tr("_", "-")
  end
end
