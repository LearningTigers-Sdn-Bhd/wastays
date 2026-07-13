# frozen_string_literal: true

module PanelsUI
  class ProfileMenu < PanelsUI::BaseComponent
    Item = Data.define(:label, :href, :icon, :method, :variant, :attributes)

    def initialize(id:, display_name:, secondary_text:, trigger_label:, trigger_icon: "user",
                   menu_class: nil)
      @id = id
      @display_name = display_name
      @secondary_text = secondary_text
      @trigger_label = trigger_label
      @trigger_icon = trigger_icon
      @menu_class = menu_class
      @items = []
      @sign_out = nil
    end

    def with_item(label:, href:, icon:, method: nil, variant: :default, **attributes)
      @items << Item.new(label:, href:, icon:, method:, variant:, attributes:)
    end

    def with_sign_out(label:, path:, method: :delete, icon: "log-out")
      @sign_out = Item.new(
        label:,
        href: path,
        icon:,
        method:,
        variant: :default,
        attributes: {}
      )
    end

    def call
      # Evaluate the render block first so the builder-style with_item and
      # with_sign_out calls populate the menu before it is composed.
      content

      render PanelsUI::DropdownMenu.new(
        id: @id,
        placement: :bottom_end,
        offset: 8,
        class: tw_merge("panel-profile-menu__menu", @menu_class)
      ) do |menu|
        menu.with_trigger(
          variant: :ghost,
          size: :sm,
          aria_label: @trigger_label,
          class: "panel-profile-menu__trigger"
        ) { avatar(size: :sm) }

        menu.with_header { account_summary }

        @items.each { |item| add_item(menu, item) }
        if @sign_out
          menu.with_separator if @items.any?
          add_item(menu, @sign_out)
        end
      end
    end

    private

    def add_item(menu, item)
      menu.with_item(
        href: item.href,
        method: item.method,
        variant: item.variant,
        **item.attributes
      ) { item_content(item) }
    end

    def account_summary
      tag.div(class: "panel-profile-menu__summary") do
        safe_join([
          avatar(size: :md),
          tag.div(class: "panel-profile-menu__identity") do
            safe_join([
              tag.p(@display_name, class: "panel-profile-menu__name"),
              tag.p(@secondary_text, class: "panel-profile-menu__secondary")
            ])
          end
        ])
      end
    end

    def avatar(size:)
      tag.span(class: "panel-profile-menu__avatar", data: { size: }) do
        helpers.app_icon(@trigger_icon, class: "panel-profile-menu__avatar-icon", aria: { hidden: "true" })
      end
    end

    def item_content(item)
      safe_join([
        helpers.app_icon(item.icon, class: "panel-profile-menu__item-icon", aria: { hidden: "true" }),
        tag.span(item.label, class: "dropdown-menu__item-label")
      ])
    end
  end
end
