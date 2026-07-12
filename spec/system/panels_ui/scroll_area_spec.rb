# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::ScrollArea", type: :system do
  before { visit "/system-design" }

  let(:root) { find("#sd-scroll-area-vertical-panel-light") }
  let(:viewport) { root.find(".panel-scroll-area__viewport") }

  it "renders the showcase in both themes with vertical and horizontal examples" do
    expect(page).to have_css("#scroll-area-preview-heading", text: "Scroll area")
    expect(page).to have_css("[data-scroll-area-preview-theme='panel-light'] .panel-scroll-area", count: 2)
    expect(page).to have_css("[data-scroll-area-preview-theme='panel-dark'] .panel-scroll-area", count: 2)
    expect(page).to have_css("#sd-scroll-area-vertical-panel-light[data-orientation='vertical']")
    expect(page).to have_css("#sd-scroll-area-horizontal-panel-light[data-orientation='horizontal']")
  end

  it "detects vertical overflow and sizes the thumb proportionally" do
    thumb_height = page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector("#sd-scroll-area-vertical-panel-light .panel-scroll-area__thumb")
        return bar.getBoundingClientRect().height
      })()
    JS

    expect(root["data-has-overflow-y"]).to eq("true")
    expect(page).to have_css(
      "#sd-scroll-area-vertical-panel-light .panel-scroll-area__scrollbar[data-visible='true']",
      visible: :all
    )
    expect(thumb_height).to be > 0
    # Content overflows the 10rem viewport, so the thumb is shorter than the track.
    expect(thumb_height).to be < viewport.evaluate_script("this.clientHeight")
  end

  it "moves the thumb as the viewport scrolls natively" do
    before_transform = thumb_transform

    viewport.execute_script("this.scrollTop = this.scrollHeight")

    # The scroll event repositions the thumb; poll until the transform changes.
    expect(page).to have_css(
      "#sd-scroll-area-vertical-panel-light[data-overflow-y-start='true']", wait: 2
    )
    expect(thumb_transform).not_to eq(before_transform)
  end

  it "reveals the scrollbar on hover and marks the root" do
    root.hover
    expect(root["data-hovering"]).to eq("")
  end

  def thumb_transform
    page.evaluate_script(<<~JS)
      getComputedStyle(
        document.querySelector("#sd-scroll-area-vertical-panel-light .panel-scroll-area__thumb[data-orientation='vertical']")
      ).transform
    JS
  end
end
