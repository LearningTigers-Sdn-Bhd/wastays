# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Tooltip, type: :component do
  def render_tooltip(**args)
    render_inline(described_class.new(**{ text: "Copy to clipboard", id: "tip" }.merge(args))) do
      "<button type=\"button\">Trigger</button>".html_safe
    end
  end

  it "wires the controller, values, and hover/focus action contract" do
    render_tooltip

    expect(page).to have_css("span.tooltip-root[data-controller='panels-ui--tooltip']")
    root = page.find("span.tooltip-root")
    expect(root["data-panels-ui--tooltip-placement-value"]).to eq("top")
    expect(root["data-panels-ui--tooltip-offset-value"]).to eq("6.0")
    expect(root["data-panels-ui--tooltip-delay-value"]).to eq("120")
    expect(root["data-panels-ui--tooltip-tooltip-id-value"]).to eq("tip")
    expect(root["data-action"]).to include("mouseenter->panels-ui--tooltip#show")
    expect(root["data-action"]).to include("focusin->panels-ui--tooltip#show")
    expect(root["data-action"]).to include("keydown->panels-ui--tooltip#onKeydown")
  end

  it "renders the trigger content alongside a closed popover bubble" do
    render_tooltip

    expect(page).to have_button("Trigger")
    expect(page).to have_css(
      "#tip[role='tooltip'][popover='manual'][data-state='closed'][data-panels-ui--tooltip-target='bubble']",
      text: "Copy to clipboard",
      visible: :all
    )
  end

  it "renders an arrow target by default" do
    render_tooltip

    expect(page).to have_css(
      "#tip .floating-arrow[aria-hidden='true'][data-panels-ui--tooltip-target='arrow']",
      visible: :all
    )
  end

  it "omits the arrow when arrow: false" do
    render_tooltip(arrow: false)

    expect(page).to have_no_css("#tip .floating-arrow", visible: :all)
  end

  it "normalizes placement for Floating UI and merges bubble classes" do
    render_tooltip(placement: :bottom_end, class: "max-w-xs")

    expect(page).to have_css("span.tooltip-root[data-panels-ui--tooltip-placement-value='bottom-end']")
    expect(page.find("#tip", visible: :all)[:class]).to include("max-w-xs")
  end

  it "merges root classes separately from bubble classes" do
    render_tooltip(root_class: "w-full", class: "max-w-xs")

    expect(page.find("span.tooltip-root")[:class]).to include("w-full")
    expect(page.find("#tip", visible: :all)[:class]).to include("max-w-xs")
    expect(page.find("#tip", visible: :all)[:class]).not_to include("w-full")
  end

  it "falls back to a top placement for an unknown placement" do
    render_tooltip(placement: :nowhere)

    expect(page).to have_css("span.tooltip-root[data-panels-ui--tooltip-placement-value='top']")
  end

  it "derives a stable tooltip id when none is given" do
    render_inline(described_class.new(text: "Auto")) { "<button>x</button>".html_safe }

    id = page.find("[role='tooltip']", visible: :all)[:id]
    expect(id).to match(/\Atooltip-\d+\z/)
  end
end
