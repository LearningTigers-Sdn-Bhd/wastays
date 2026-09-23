# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::StatusBadge, type: :component do
  it "draws the word with an icon and the tone" do
    render_inline(described_class.new(label: "Checked in", tone: :success, icon: "door-open"))

    expect(page).to have_css("span.guest-status-badge[data-tone='success'] svg[aria-hidden='true']")
    expect(page).to have_css(".guest-status-badge", text: "Checked in")
  end

  it "falls back to muted for an unknown tone" do
    render_inline(described_class.new(label: "Odd", tone: :purple))

    expect(page).to have_css(".guest-status-badge[data-tone='muted']", text: "Odd")
  end
end
