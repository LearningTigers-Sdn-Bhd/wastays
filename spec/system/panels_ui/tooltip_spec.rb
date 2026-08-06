# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Tooltip", type: :system do
  before { visit_when_loaded "/system-design?only=tooltip_preview" }

  let(:trigger) { find_button("Hover or focus me") }

  def send_key(key)
    page.execute_script(<<~JS)
      document.activeElement.dispatchEvent(new KeyboardEvent("keydown", { key: #{key.to_json}, bubbles: true }))
    JS
  end

  it "reveals the label on hover and hides it on mouse leave" do
    trigger.hover
    expect(page).to have_css("[role='tooltip']:popover-open", text: "Copy to clipboard")

    find("h1", text: "PanelsUI").hover
    expect(page).to have_no_css("[role='tooltip']:popover-open", text: "Copy to clipboard")
  end

  it "reveals on keyboard focus and dismisses on Escape" do
    page.execute_script("arguments[0].focus()", trigger)
    expect(page).to have_css("[role='tooltip']:popover-open", text: "Copy to clipboard")

    send_key("Escape")
    expect(page).to have_no_css("[role='tooltip']:popover-open", text: "Copy to clipboard")
  end

  it "hides again when focus leaves the trigger" do
    page.execute_script("arguments[0].focus()", trigger)
    expect(page).to have_css("[role='tooltip']:popover-open", text: "Copy to clipboard")

    page.execute_script("document.activeElement.blur()")
    expect(page).to have_no_css("[role='tooltip']:popover-open", text: "Copy to clipboard")
  end

  it "positions the arrow against the trigger side once shown" do
    trigger.hover
    expect(page).to have_css("[role='tooltip']:popover-open", text: "Copy to clipboard")

    # Default placement is top, so Floating UI pins the arrow to the bubble's bottom edge.
    arrow_bottom = page.evaluate_script(<<~JS)
      document.querySelector("[role='tooltip']:popover-open .floating-arrow").style.bottom
    JS
    expect(arrow_bottom).to match(/-?\d/)
  end

  it "wires aria-describedby from the trigger to the tooltip bubble" do
    described_by = trigger["aria-describedby"]
    expect(described_by).to be_present

    bubble = find("##{described_by}", visible: :all)
    expect(bubble).to match_css("[role='tooltip']")
    expect(bubble.text(:all)).to eq("Copy to clipboard")
  end
end
