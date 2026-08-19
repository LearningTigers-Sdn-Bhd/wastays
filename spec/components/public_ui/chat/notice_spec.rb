# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Notice, type: :component do
  it "renders muted text by default" do
    render_inline(described_class.new(text: "Someone will reply here shortly."))

    expect(page).to have_css("p.public-chat__notice[data-tone='muted']", text: "Someone will reply here shortly.")
  end

  it "warms up when a person takes the thread" do
    render_inline(described_class.new(tone: :accent)) { "Farah from the front desk joined." }

    expect(page).to have_css(".public-chat__notice[data-tone='accent']", text: "Farah from the front desk joined.")
  end

  it "falls back to muted for an unknown tone" do
    render_inline(described_class.new(text: "Anything", tone: :neon))

    expect(page).to have_css(".public-chat__notice[data-tone='muted']")
  end
end
