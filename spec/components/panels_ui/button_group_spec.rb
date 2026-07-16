# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::ButtonGroup, type: :component do
  ButtonGroupObject = Class.new do
    include ActiveModel::Model
    attr_accessor :query, :currency
  end

  def form_for(object = ButtonGroupObject.new)
    ActionView::Helpers::FormBuilder.new(:filters, object, vc_test_view_context, {})
  end

  def render_component(component, &block)
    vc_test_view_context.render(component, &block)
  end

  def join_components(components)
    vc_test_view_context.safe_join(components)
  end

  it "renders an accessible horizontal group with passthrough attributes" do
    render_inline(
      described_class.new(
        id: "booking-actions",
        class: "w-full",
        data: { controller: "actions" },
        aria: { label: "Booking actions" }
      )
    ) { "Actions" }

    group = page.find("#booking-actions")
    expect(group[:role]).to eq("group")
    expect(group[:class]).to include("panel-button-group", "w-full")
    expect(group["data-slot"]).to eq("button-group")
    expect(group["data-orientation"]).to eq("horizontal")
    expect(group["data-controller"]).to eq("actions")
    expect(group["aria-label"]).to eq("Booking actions")
  end

  it "supports vertical groups and falls back to horizontal" do
    render_inline(described_class.new(orientation: :vertical)) { "Vertical" }
    expect(page.find("[role='group']")["data-orientation"]).to eq("vertical")

    render_inline(described_class.new(orientation: :diagonal)) { "Fallback" }
    expect(page.find("[role='group']", text: "Fallback")["data-orientation"]).to eq("horizontal")
  end

  it "supports nested button groups and button composition" do
    render_inline(described_class.new(aria: { label: "Nested actions" })) do
      join_components([
        render_component(described_class.new(aria: { label: "Editing" })) do
          join_components([
            render_component(PanelsUI::Button.new(variant: :neutral)) { "Copy" },
            render_component(PanelsUI::Button.new(variant: :neutral)) { "Paste" }
          ])
        end,
        render_component(described_class.new(aria: { label: "History" })) do
          render_component(PanelsUI::Button.new(variant: :neutral)) { "Undo" }
        end
      ])
    end

    expect(page).to have_css(".panel-button-group > .panel-button-group", count: 2)
    expect(page).to have_css(".panel-button-group .panel-button", count: 3)
  end

  it "renders text as a div, span, or associated label" do
    render_inline(described_class::Text.new) { "Prefix" }
    expect(page).to have_css("div.panel-button-group__text[data-slot='button-group-text']", text: "Prefix")

    render_inline(described_class::Text.new(as: :span)) { "Inline" }
    expect(page).to have_css("span.panel-button-group__text", text: "Inline")

    render_inline(described_class::Text.new(as: :label, for: "filters_query", class: "currency")) { "$" }
    label = page.find("label.panel-button-group__text")
    expect(label[:for]).to eq("filters_query")
    expect(label[:class]).to include("currency")

    render_inline(described_class::Text.new(as: :script)) { "Safe fallback" }
    expect(page).to have_css("div.panel-button-group__text", text: "Safe fallback")
  end

  it "renders decorative separators with normalized orientation" do
    render_inline(described_class::Separator.new)
    separator = page.find(".panel-button-group__separator", visible: :all)
    expect(separator["data-slot"]).to eq("button-group-separator")
    expect(separator["data-orientation"]).to eq("vertical")
    expect(separator["aria-hidden"]).to eq("true")
    expect(separator[:role]).to be_nil

    render_inline(described_class::Separator.new(orientation: :horizontal, class: "my-separator"))
    separator = page.find(".panel-button-group__separator[data-orientation='horizontal']", visible: :all)
    expect(separator[:class]).to include("my-separator")

    render_inline(described_class::Separator.new(orientation: :diagonal))
    expect(page.find(".panel-button-group__separator", visible: :all)["data-orientation"]).to eq("vertical")
  end

  it "composes inputs, select menus, dropdown menus, and popovers" do
    builder = form_for

    render_inline(described_class.new(class: "w-full", aria: { label: "Search tools" })) do
      join_components([
        render_component(described_class::Text.new(as: :label, for: "filters_query")) { "Search" },
        render_component(PanelsUI::Input.new(form: builder, attribute: :query)),
        render_component(PanelsUI::SelectMenu.new(
          form: builder,
          attribute: :currency,
          choices: [ [ "MYR", "myr" ], [ "USD", "usd" ] ]
        )),
        render_component(PanelsUI::DropdownMenu.new(id: "group-menu")) do |menu|
          menu.with_trigger(variant: :neutral, aria_label: "More actions") { "More" }
          menu.with_item { "Export" }
        end,
        render_component(PanelsUI::Popover.new(id: "group-popover")) do |popover|
          popover.with_trigger(variant: :neutral) { "Help" }
          "Popover body"
        end
      ])
    end

    expect(page).to have_css(".panel-button-group > .panel-input")
    expect(page).to have_css(".panel-button-group > .panel-select-menu")
    expect(page).to have_css(".panel-button-group > .dropdown-menu-root > .panel-button")
    expect(page).to have_css(".panel-button-group > .popover-root > .panel-button")
  end
end
