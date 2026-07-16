# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Popover, type: :component do
  def render_popover(trigger_args: {}, **args)
    render_inline(described_class.new(**{ id: "pop" }.merge(args))) do |popover|
      popover.with_trigger(**trigger_args) { "Open" }
      "<p>Body content</p>".html_safe
    end
  end

  it "wires the controller, values, and the trigger/panel contract" do
    render_popover

    expect(page).to have_css("span.popover-root[data-controller='panels-ui--popover']")
    root = page.find("span.popover-root")
    expect(root["data-panels-ui--popover-placement-value"]).to eq("bottom")
    expect(root["data-panels-ui--popover-offset-value"]).to eq("8.0")
    expect(root["data-panels-ui--popover-trigger-on-value"]).to eq("click")
    expect(root["data-panels-ui--popover-close-delay-value"]).to eq("0")
    expect(root["data-panels-ui--popover-focus-value"]).to eq("false")

    trigger = page.find("#pop-trigger")
    expect(trigger["aria-haspopup"]).to eq("dialog")
    expect(trigger["aria-controls"]).to eq("pop-panel")
    expect(trigger["data-action"]).to include("click->panels-ui--popover#toggle")
    expect(trigger["data-action"]).to include("keydown->panels-ui--popover#onTriggerKeydown")
  end

  it "supports a headless trigger without button variant or size styling" do
    render_popover(trigger_args: { unstyled: true, class: "sidebar-link" })

    trigger = page.find("#pop-trigger")
    expect(trigger[:class]).to include("popover__trigger", "sidebar-link")
    expect(trigger[:class]).not_to include("panel-button")
    expect(trigger["data-variant"]).to be_nil
    expect(trigger["data-size"]).to be_nil
    expect(trigger["data-action"]).to include("click->panels-ui--popover#toggle")
    expect(trigger["aria-controls"]).to eq("pop-panel")
  end

  it "supports a hover/focus link trigger and caller attributes on the root" do
    render_popover(
      trigger_on: :hover,
      root_class: "timeline-segment",
      style: "grid-column: 2 / 6",
      data: { tone: "success" },
      trigger_args: { href: "/bookings/1", unstyled: true, aria_label: "Open Ada's booking" }
    )

    root = page.find("#pop")
    expect(root[:class]).to include("timeline-segment")
    expect(root[:style]).to eq("grid-column: 2 / 6")
    expect(root["data-tone"]).to eq("success")
    expect(page).to have_link("Open", href: "/bookings/1")
    expect(page.find("#pop-trigger")["aria-label"]).to eq("Open Ada's booking")
    expect(page.find("#pop-trigger")["data-action"]).to be_nil
  end

  it "renders the trigger content alongside a closed dialog panel" do
    render_popover

    expect(page).to have_button("Open")
    expect(page).to have_css(
      "#pop-panel[role='dialog'][popover='manual'][data-state='closed'][data-panels-ui--popover-target='panel']",
      text: "Body content",
      visible: :all
    )
  end

  it "renders an arrow target by default" do
    render_popover

    expect(page).to have_css(
      "#pop-panel .floating-arrow[aria-hidden='true'][data-panels-ui--popover-target='arrow']",
      visible: :all
    )
  end

  it "omits the arrow when arrow: false" do
    render_popover(arrow: false)

    expect(page).to have_no_css("#pop-panel .floating-arrow", visible: :all)
  end

  it "normalizes placement for Floating UI and merges panel classes" do
    render_popover(placement: :top_end, class: "w-72")

    expect(page).to have_css("span.popover-root[data-panels-ui--popover-placement-value='top-end']")
    expect(page.find("#pop-panel", visible: :all)[:class]).to include("w-72")
  end

  it "merges root classes separately from panel classes" do
    render_popover(root_class: "w-full", class: "w-72")

    expect(page.find("span.popover-root")[:class]).to include("w-full")
    expect(page.find("#pop-panel", visible: :all)[:class]).to include("w-72")
    expect(page.find("#pop-panel", visible: :all)[:class]).not_to include("w-full")
  end

  it "can omit dialog semantics for a disclosure-style popup" do
    render_popover(role: nil, aria_haspopup: nil)

    expect(page.find("#pop-trigger")["aria-haspopup"]).to be_nil
    expect(page.find("#pop-panel", visible: :all)["role"]).to be_nil
    expect(page.find("#pop-trigger")["aria-controls"]).to eq("pop-panel")
  end

  it "falls back to a bottom placement for an unknown placement" do
    render_popover(placement: :nowhere)

    expect(page).to have_css("span.popover-root[data-panels-ui--popover-placement-value='bottom']")
  end

  it "wires hover-open actions onto the root when trigger_on: :hover" do
    render_popover(trigger_on: :hover, close_delay: 180)

    root = page.find("span.popover-root")
    expect(root["data-panels-ui--popover-trigger-on-value"]).to eq("hover")
    expect(root["data-panels-ui--popover-close-delay-value"]).to eq("180")
    expect(root["data-action"]).to include("mouseenter->panels-ui--popover#show")
    expect(root["data-action"]).to include("focusout->panels-ui--popover#hide")
  end

  it "does not put hover actions on the root for the default click trigger" do
    render_popover

    expect(page.find("span.popover-root")["data-action"]).to be_nil
  end

  it "traps focus and forces a click trigger when focus: true" do
    render_popover(focus: true, trigger_on: :hover)

    root = page.find("span.popover-root")
    expect(root["data-panels-ui--popover-focus-value"]).to eq("true")
    # A hover-open focus trap makes no sense, so it downgrades to a click trigger.
    expect(root["data-panels-ui--popover-trigger-on-value"]).to eq("click")
    expect(root["data-action"]).to be_nil
    expect(page.find("#pop-panel", visible: :all)["aria-modal"]).to eq("true")
  end
end
