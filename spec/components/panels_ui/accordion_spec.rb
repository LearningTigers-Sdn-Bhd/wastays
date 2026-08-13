# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Accordion, type: :component do
  def render_accordion(**options)
    defaults = { id: "policies", heading_level: 3, type: :single, collapsible: true }
    render_inline(described_class.new(**defaults.merge(options))) do |accordion|
      accordion.with_item(value: "cancellation", region: true) do |item|
        item.with_trigger { "Cancellation policy" }
        item.with_body { '<a href="#terms">Read terms</a>'.html_safe }
      end
      accordion.with_item(value: "payment", disabled: true) do |item|
        item.with_trigger { "Payment policy" }
        item.with_body { "Payment details" }
      end
    end
  end

  it "renders accessible headings, triggers, panels, and an ornamental indicator" do
    render_accordion(default_open: [ "cancellation" ])

    expect(page).to have_css("#policies.panel-accordion--default[data-controller='panels-ui--accordion']")
    expect(page).to have_css("h3.panel-collapsible__heading > button#policies-item-1-trigger[aria-expanded='true'][aria-controls='policies-item-1-content']", text: "Cancellation policy")
    expect(page).to have_css("#policies-item-1-content[role='region'][aria-labelledby='policies-item-1-trigger']:not([hidden]):not([inert])")
    expect(page).to have_css("#policies-item-1-trigger .panel-accordion__indicator[aria-hidden='true']")
    expect(page).to have_css("#policies-item-2-trigger[disabled][aria-expanded='false']", text: "Payment policy")
    expect(page).to have_css("#policies-item-2-content[hidden][inert]", visible: :all)
  end

  it "defaults a non-collapsible single accordion to its first enabled item" do
    render_accordion(collapsible: false)

    expect(page).to have_css("#policies-item-1-trigger[aria-expanded='true'][aria-disabled='true']")
    expect(page).to have_css("#policies-item-1-content:not([hidden]):not([inert])")
  end

  it "renders the bordered variant and merges caller attributes" do
    render_accordion(
      variant: :bordered,
      class: "mt-4",
      aria: { label: "Booking policies" },
      data: { controller: "analytics", testid: "policies" }
    )

    expect(page).to have_css("#policies.panel-accordion--bordered.mt-4[aria-label='Booking policies'][data-testid='policies']")
    expect(page.find("#policies")["data-controller"]).to eq("analytics panels-ui--accordion")
  end

  it "supports multiple initially open items" do
    render_inline(described_class.new(id: "settings", heading_level: 4, type: :multiple, default_open: %w[email sms])) do |accordion|
      %w[email sms].each do |value|
        accordion.with_item(value: value) do |item|
          item.with_trigger { value.upcase }
          item.with_body { "#{value} settings" }
        end
      end
    end

    expect(page).to have_css("#settings h4", count: 2)
    expect(page).to have_css("#settings [data-accordion-item][data-state='open']", count: 2)
    expect(page).to have_css("#settings [aria-disabled]", count: 0)
  end

  it "forwards item header content, header styling, and caller attributes" do
    render_inline(described_class.new(id: "inventory", heading_level: 3, type: :single, collapsible: true)) do |accordion|
      accordion.with_item(
        value: "deluxe",
        id: "inventory-deluxe",
        region: true,
        header_class: "grid-cols-2",
        data: { room_type_id: 42 },
        aria: { label: "Deluxe inventory" }
      ) do |item|
        item.with_trigger { "Deluxe" }
        item.with_header_content { '<span data-testid="group">Villas</span>'.html_safe }
        item.with_body { "Rates" }
      end
    end

    expect(page).to have_css("#inventory-deluxe[data-room-type-id='42'][data-accordion-item][data-accordion-value='deluxe'][aria-label='Deluxe inventory']")
    expect(page).to have_css("#inventory-deluxe > .panel-collapsible__header.grid-cols-2 [data-testid='group']", text: "Villas")
    expect(page).to have_css("#inventory-deluxe-trigger[aria-expanded='false'][aria-controls='inventory-deluxe-content']", text: "Deluxe")
    expect(page).to have_css("#inventory-deluxe-content[role='region'][hidden][inert]", visible: :all)
  end

  it "requires trigger and body slots" do
    expect do
      render_inline(described_class.new(heading_level: 3, collapsible: true)) do |accordion|
        accordion.with_item(value: "incomplete") { |item| item.with_trigger { "Trigger" } }
      end
    end.to raise_error(ArgumentError, "Accordion item requires a body slot")
  end

  it "validates structural options and item state" do
    cases = [
      [ { heading_level: 1 }, "Accordion heading_level must be between 2 and 6" ],
      [ { heading_level: 3, variant: :card }, "Accordion variant must be one of: default, bordered" ],
      [ { heading_level: 3, type: :many }, "Accordion type must be one of: single, multiple" ],
      [ { heading_level: 3, type: :multiple, collapsible: true }, "Accordion multiple type does not accept collapsible" ],
      [ { heading_level: 3, type: :single, default_open: %w[one two] }, "Accordion single type accepts at most one default_open value" ],
      [ { heading_level: 3, collapsible: true, default_open: [ "missing" ] }, "Accordion default_open contains unknown values: missing" ]
    ]

    cases.each do |options, message|
      expect do
        render_inline(described_class.new(**options)) do |accordion|
          %w[one two].each do |value|
            accordion.with_item(value: value) do |item|
              item.with_trigger { value }
              item.with_body { "body" }
            end
          end
        end
      end.to raise_error(ArgumentError, message)
    end
  end

  it "rejects duplicate, blank, disabled, and unavailable defaults" do
    expect do
      render_inline(described_class.new(heading_level: 3, collapsible: true)) do |accordion|
        2.times do
          accordion.with_item(value: "same") do |item|
            item.with_trigger { "Same" }
            item.with_body { "Body" }
          end
        end
      end
    end.to raise_error(ArgumentError, "Accordion item values must be unique")

    expect do
      render_inline(described_class.new(heading_level: 3, collapsible: true, default_open: [ "off" ])) do |accordion|
        accordion.with_item(value: "off", disabled: true) do |item|
          item.with_trigger { "Off" }
          item.with_body { "Body" }
        end
      end
    end.to raise_error(ArgumentError, "Accordion default_open cannot include disabled items: off")
  end
end
