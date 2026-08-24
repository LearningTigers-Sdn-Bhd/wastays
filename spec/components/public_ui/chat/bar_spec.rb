# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Bar, type: :component do
  it "names the hotel the guest is talking to, and who is answering" do
    render_inline(described_class.new(
      title: "Aurora Crown Resort",
      status: { text: "Our front desk replies here" }
    ))

    expect(page).to have_css(".public-chat__bar-title", text: "Aurora Crown Resort")
    expect(page).to have_css(".public-chat__status", text: "Our front desk replies here")
  end

  it "offers a way back out when it is given one" do
    render_inline(described_class.new(title: "Aurora Crown Resort", back_path: "/concierge/aurora"))

    expect(page).to have_css("a.public-chat__bar-back[href='/concierge/aurora'][aria-label='Back']")
  end

  it "leaves the way out off a page that has nowhere to go back to" do
    render_inline(described_class.new(title: "Aurora Crown Resort"))

    expect(page).to have_no_css(".public-chat__bar-back")
  end

  it "holds actions on the whole conversation" do
    render_inline(described_class.new(title: "Aurora Crown Resort")) do |bar|
      bar.with_menu { "MENU" }
    end

    expect(page).to have_css(".public-chat__bar-actions", text: "MENU")
  end

  it "leaves the actions box out rather than rendering an empty one" do
    render_inline(described_class.new(title: "Aurora Crown Resort"))

    expect(page).to have_no_css(".public-chat__bar-actions")
  end
end
