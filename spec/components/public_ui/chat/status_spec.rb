# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Status, type: :component do
  it "says who is answering, under a stable id a live update can find" do
    render_inline(described_class.new(text: "Our front desk replies here"))

    expect(page).to have_css("p#concierge-chat-status.public-chat__status", text: "Our front desk replies here")
    expect(page).to have_css(".public-chat__status[data-tone='muted']")
  end

  it "marks a person holding the thread as worth noticing" do
    render_inline(described_class.new(text: "Farah is answering you now", tone: :accent))

    expect(page).to have_css(".public-chat__status[data-tone='accent']")
  end

  it "refuses a tone it does not have a colour for" do
    render_inline(described_class.new(text: "Anything", tone: :neon))

    expect(page).to have_css(".public-chat__status[data-tone='muted']")
  end
end
