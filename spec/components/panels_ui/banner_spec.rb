# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Banner, type: :component do
  it "renders the default static full banner" do
    render_inline(described_class.new(title: "Announcement")) do |banner|
      banner.with_description { "Details" }
    end

    expect(page).to have_css("aside.panel-banner[role='status'][data-tone='default']" \
                             "[data-appearance='full'][data-strategy='static'][data-position='top']")
    expect(page).to have_css(".panel-banner__title", text: "Announcement")
    expect(page).to have_css(".panel-banner__description", text: "Details")
    expect(page).to have_css(".panel-banner__icon svg")
  end

  it "renders floating fixed bottom placement with actions and dismissal" do
    render_inline(described_class.new(
      tone: :warning, appearance: :floating, strategy: :fixed, position: :bottom,
      title: "Attention", dismissible: true
    )) do |banner|
      banner.with_actions { '<button type="button">Act</button>'.html_safe }
    end

    expect(page).to have_css(".panel-banner[data-tone='warning'][data-appearance='floating']" \
                             "[data-strategy='fixed'][data-position='bottom']" \
                             "[data-controller='panels-ui--dismissible']")
    expect(page).to have_button("Act")
    expect(page).to have_css("button[aria-label='Dismiss banner']")
  end

  it "supports a custom icon, hides the default, and merges HTML attributes" do
    render_inline(described_class.new(id: "offer", class: "max-w-xl", data: { campaign: "summer" })) do |banner|
      banner.with_icon { '<span class="custom-icon">%</span>'.html_safe }
    end

    banner = page.find("#offer.panel-banner.max-w-xl[data-campaign='summer']")
    expect(banner).to have_css(".custom-icon", text: "%")
    expect(banner).to have_css(".panel-banner__icon svg", count: 0)
  end

  it "can suppress its icon" do
    render_inline(described_class.new(show_icon: false, title: "No icon"))

    expect(page).to have_no_css(".panel-banner__icon")
  end

  it "falls back for unknown enum values" do
    render_inline(described_class.new(
      tone: :unknown, appearance: :unknown, strategy: :unknown, position: :unknown,
      title: "Fallback"
    ))

    expect(page).to have_css(".panel-banner[data-tone='default'][data-appearance='full']" \
                             "[data-strategy='static'][data-position='top']")
  end
end
