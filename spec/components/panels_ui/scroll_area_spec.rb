# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::ScrollArea, type: :component do
  def render_scroll_area(**options)
    render_inline(described_class.new(**options)) do
      '<p>Scrollable content</p>'.html_safe
    end
  end

  it "renders the four-part vertical structure with native scroll preserved" do
    render_scroll_area

    expect(page).to have_css(
      ".panel-scroll-area[data-controller='panels-ui--scroll-area']" \
      "[data-orientation='vertical'][data-scroll-fade='none']" \
      "[data-panels-ui--scroll-area-target='root']"
    )
    expect(page).to have_css(
      ".panel-scroll-area__viewport[data-panels-ui--scroll-area-target='viewport'][tabindex='0']",
      text: "Scrollable content"
    )
    expect(page).to have_css(
      ".panel-scroll-area__scrollbar[data-orientation='vertical'][aria-hidden='true']"
    )
    expect(page).to have_css(
      ".panel-scroll-area__scrollbar[data-orientation='vertical'] .panel-scroll-area__thumb[aria-hidden='true']"
    )
  end

  it "defaults the hide delay and exposes it as a Stimulus value" do
    render_scroll_area

    expect(page).to have_css(".panel-scroll-area[data-panels-ui--scroll-area-hide-delay-value='600']")
  end

  it "accepts a custom hide delay" do
    render_scroll_area(hide_delay: 250)

    expect(page).to have_css(".panel-scroll-area[data-panels-ui--scroll-area-hide-delay-value='250']")
  end

  it "renders only the horizontal scrollbar for horizontal orientation" do
    render_scroll_area(orientation: :horizontal)

    expect(page).to have_css(".panel-scroll-area[data-orientation='horizontal']")
    expect(page).to have_css(".panel-scroll-area__scrollbar[data-orientation='horizontal']")
    expect(page).to have_no_css(".panel-scroll-area__scrollbar[data-orientation='vertical']")
  end

  it "renders both scrollbars for orientation :both" do
    render_scroll_area(orientation: :both)

    expect(page).to have_css(".panel-scroll-area__scrollbar[data-orientation='vertical']")
    expect(page).to have_css(".panel-scroll-area__scrollbar[data-orientation='horizontal']")
  end

  it "falls back to sensible defaults for unknown variant values" do
    render_scroll_area(orientation: :diagonal, scroll_fade: :sparkle)

    expect(page).to have_css(".panel-scroll-area[data-orientation='vertical'][data-scroll-fade='none']")
  end

  it "sets the scroll fade data attribute" do
    render_scroll_area(scroll_fade: :y)

    expect(page).to have_css(".panel-scroll-area[data-scroll-fade='y']")
  end

  it "applies height and viewport classes to the viewport" do
    render_scroll_area(height: "h-72", max_height: "max-h-96", viewport_class: "px-4")

    expect(page).to have_css(".panel-scroll-area__viewport.h-72.max-h-96.px-4")
  end

  it "stacks a caller controller ahead of the scroll area controller" do
    render_inline(described_class.new(data: { controller: "analytics", testid: "list" })) do
      "content".html_safe
    end

    root = page.find(".panel-scroll-area")
    expect(root["data-controller"]).to eq("analytics panels-ui--scroll-area")
    expect(root["data-testid"]).to eq("list")
  end

  it "merges caller classes onto the root" do
    render_scroll_area(class: "mt-4 border")

    expect(page).to have_css(".panel-scroll-area.mt-4.border")
  end
end
