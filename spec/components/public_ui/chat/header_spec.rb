# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Header, type: :component do
  it "names the hotel the guest is talking to" do
    render_inline(described_class.new(title: "Aurora Crown Resort"))

    expect(page).to have_css(".public-chat__header-title", text: "Aurora Crown Resort")
  end

  it "adds a line about who answers when there is one" do
    render_inline(described_class.new(title: "Aurora Crown Resort", subtitle: "Our front desk replies here"))

    expect(page).to have_css(".public-chat__header-subtitle", text: "Our front desk replies here")
  end

  it "leaves the line out rather than rendering an empty one" do
    render_inline(described_class.new(title: "Aurora Crown Resort", subtitle: " "))

    expect(page).to have_no_css(".public-chat__header-subtitle")
  end
end
