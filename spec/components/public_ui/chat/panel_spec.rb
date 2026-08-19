# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Panel, type: :component do
  let(:hotel) { build_stubbed(:hotel, name: "Aurora Crown Resort") }

  it "composes thread, notice and composer under one chat controller" do
    render_inline(described_class.new) do |panel|
      panel.with_log(messages: [], hotel: hotel)
      panel.with_notice(text: "Your message goes straight to our front desk.")
      panel.with_composer(url: "/concierge/aurora/chat")
    end

    expect(page).to have_css("div.public-chat[data-controller='concierge-chat']")
    expect(page).to have_css(".public-chat ol.public-chat__log")
    expect(page).to have_css(".public-chat__notice", text: "straight to our front desk")
    expect(page).to have_css("form.public-chat__composer[action='/concierge/aurora/chat']")
  end

  it "leaves the notice out when there is nothing to say" do
    render_inline(described_class.new) do |panel|
      panel.with_log(messages: [], hotel: hotel)
      panel.with_composer(url: "/concierge/aurora/chat")
    end

    expect(page).to have_no_css(".public-chat__notice")
  end

  it "accepts caller classes and attributes without losing its own" do
    render_inline(described_class.new(class: "mt-8", id: "enquiry")) do |panel|
      panel.with_log(messages: [], hotel: hotel)
      panel.with_composer(url: "/concierge/aurora/chat")
    end

    expect(page).to have_css("#enquiry.public-chat.mt-8[data-controller='concierge-chat']")
  end
end
