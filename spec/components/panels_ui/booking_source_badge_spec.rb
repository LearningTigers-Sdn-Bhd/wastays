# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::BookingSourceBadge, type: :component do
  it "renders the uploaded logo when present, regardless of badge configuration" do
    source = create(:booking_source, key: "logo_source", kind: "ota", badge_color: "#010101", badge_initial: "L")
    source.logo.attach(io: Rails.root.join("spec/fixtures/files/sample_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")

    render_inline(described_class.new(source: "logo_source", with_tooltip: false))

    expect(page).to have_css("img")
    expect(page).not_to have_css("span[role='img']")
  end

  it "falls back to the colored initial badge for an OTA source with no logo but a configured badge" do
    create(:booking_source, key: "ota_with_badge", kind: "ota", badge_color: "#010101", badge_initial: "L")

    render_inline(described_class.new(source: "ota_with_badge", with_tooltip: false))

    expect(page).not_to have_css("img")
    expect(page).to have_css("span[role='img']", text: "L")
  end

  it "falls back to the generic icon for an OTA source with no logo and no configured badge" do
    create(:booking_source, key: "ota_no_badge", kind: "ota", icon: "ticket", badge_color: nil, badge_initial: nil)

    render_inline(described_class.new(source: "ota_no_badge", with_tooltip: false))

    expect(page).not_to have_css("img")
    expect(page).not_to have_css("span[role='img']")
    expect(page).to have_css("svg")
  end

  it "falls back to the generic icon for a non-OTA source even when badge fields happen to be set" do
    create(:booking_source, key: "manual_with_stray_badge", kind: "manual", icon: "phone", badge_color: "#010101", badge_initial: "M")

    render_inline(described_class.new(source: "manual_with_stray_badge", with_tooltip: false))

    expect(page).not_to have_css("span[role='img']")
    expect(page).to have_css("svg")
  end
end
