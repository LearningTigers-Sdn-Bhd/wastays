# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Chat::Panel, type: :component do
  let(:hotel) { build_stubbed(:hotel, name: "Aurora Crown Resort") }

  it "composes bar, thread and composer under one chat controller" do
    render_inline(described_class.new) do |panel|
      panel.with_bar(title: hotel.name, status: { text: "Our front desk replies here" })
      panel.with_log(messages: [], hotel: hotel)
      panel.with_composer(url: "/concierge/aurora/chat")
    end

    expect(page).to have_css("div.guest-chat[data-controller='concierge-chat']")
    expect(page).to have_css(".guest-chat .guest-chat__bar", text: "Aurora Crown Resort")
    expect(page).to have_css(".guest-chat ol.guest-chat__log")
    expect(page).to have_css(".guest-chat__footer form.guest-chat__composer[action='/concierge/aurora/chat']")
  end

  # A refusal is about the message the guest just tried to send, so it belongs
  # where they are already looking rather than at the top of the page.
  it "keeps whatever the send had to say beside the box" do
    render_inline(described_class.new) do |panel|
      panel.with_log(messages: [], hotel: hotel)
      panel.with_alert { "That message is too long." }
      panel.with_composer(url: "/concierge/aurora/chat")
    end

    expect(page).to have_css(".guest-chat__footer", text: "That message is too long.")
  end

  # An unset mask-image is not a mask at all -- it lets everything through --
  # so the pattern has to be flagged as well as supplied, or a hotel without one
  # gets a flat wash across its chat.
  describe "the doodle behind the thread" do
    it "carries the pattern and says it has one" do
      render_inline(described_class.new(doodle: "--guest-chat-doodle: url(/assets/doodle.png);")) do |panel|
        panel.with_log(messages: [], hotel: hotel)
        panel.with_composer(url: "/concierge/aurora/chat")
      end

      expect(page).to have_css(".guest-chat[data-doodle='true'][style*='--guest-chat-doodle']")
    end

    it "says it has none rather than leaving the question open" do
      render_inline(described_class.new) do |panel|
        panel.with_log(messages: [], hotel: hotel)
        panel.with_composer(url: "/concierge/aurora/chat")
      end

      expect(page).to have_css(".guest-chat[data-doodle='false']")
      expect(page).to have_no_css(".guest-chat[style]")
    end
  end

  it "accepts caller classes and attributes without losing its own" do
    render_inline(described_class.new(class: "mt-8", id: "enquiry")) do |panel|
      panel.with_log(messages: [], hotel: hotel)
      panel.with_composer(url: "/concierge/aurora/chat")
    end

    expect(page).to have_css("#enquiry.guest-chat.mt-8[data-controller='concierge-chat']")
  end
end
