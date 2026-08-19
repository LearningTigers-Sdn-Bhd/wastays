# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Log, type: :component do
  let(:hotel) { build_stubbed(:hotel, name: "Aurora Crown Resort") }

  it "renders the thread in order, announced to screen readers" do
    messages = [
      build_stubbed(:prospect_message, sender_role: "guest", body: "Do you have parking?"),
      build_stubbed(:prospect_message, sender_role: "bot", body: "We do, it is free.")
    ]

    render_inline(described_class.new(messages: messages, hotel: hotel))

    expect(page).to have_css("ol.public-chat__log[role='log'][aria-live='polite'][aria-label='Conversation']")
    expect(page.all("li .public-chat__bubble").map(&:text)).to eq([ "Do you have parking?", "We do, it is free." ])
  end

  # The list is the anchor a live message gets appended to, so it has to exist
  # before there is anything in it.
  it "still renders the list when the conversation is empty, alongside a prompt" do
    render_inline(described_class.new(messages: [], hotel: hotel))

    expect(page).to have_css("ol#concierge-chat-log")
    expect(page).to have_css("p#concierge-chat-log-empty.public-chat__empty", text: "Ask about rooms")
  end

  it "drops the prompt once someone has spoken" do
    render_inline(described_class.new(messages: [ build_stubbed(:prospect_message, sender_role: "guest") ], hotel: hotel))

    expect(page).to have_no_css(".public-chat__empty")
  end

  it "groups what one author said in a row into a single run" do
    messages = [
      build_stubbed(:prospect_message, sender_role: "guest", body: "Do you have parking?"),
      build_stubbed(:prospect_message, sender_role: "bot", body: "We do."),
      build_stubbed(:prospect_message, sender_role: "bot", body: "It is free for guests."),
      build_stubbed(:prospect_message, sender_role: "guest", body: "Thanks!")
    ]

    render_inline(described_class.new(messages: messages, hotel: hotel))

    runs = page.all("li").map { |item| [ item["data-run-start"], item["data-run-end"] ] }
    expect(runs).to eq([ %w[true true], %w[true false], %w[false true], %w[true true] ])
    expect(page.all(".public-chat__author").map(&:text)).to eq([ "You", "Aurora Crown Resort", "You" ])
  end

  it "keeps two different people apart even when both are staff" do
    farah = build_stubbed(:user, name: "Farah")
    amir = build_stubbed(:user, name: "Amir")
    messages = [
      build_stubbed(:prospect_message, sender_role: "staff", sender_user: farah, body: "Checking now."),
      build_stubbed(:prospect_message, sender_role: "staff", sender_user: amir, body: "Room 12 is ready.")
    ]

    render_inline(described_class.new(messages: messages, hotel: hotel))

    expect(page.all("li").map { |item| item["data-run-start"] }).to eq(%w[true true])
    expect(page.all(".public-chat__author").map(&:text)).to eq([ "Farah", "Amir" ])
  end

  it "leaves a system line standing on its own between two bot replies" do
    messages = [
      build_stubbed(:prospect_message, sender_role: "bot", body: "One moment."),
      build_stubbed(:prospect_message, sender_role: "system", body: "Farah joined the chat"),
      build_stubbed(:prospect_message, sender_role: "bot", body: "Still here.")
    ]

    render_inline(described_class.new(messages: messages, hotel: hotel))

    expect(page.all("li").map { |item| item["data-run-end"] }).to eq(%w[true true true])
  end

  it "takes an id and label so a page can host more than one thread" do
    render_inline(described_class.new(messages: [], hotel: hotel, id: "thread-7", label: "Booking enquiry"))

    expect(page).to have_css("ol#thread-7[aria-label='Booking enquiry']")
    expect(page).to have_css("p#thread-7-empty")
  end

  it "wires the scroll target the chat controller looks for" do
    render_inline(described_class.new(messages: [], hotel: hotel))

    expect(page).to have_css("ol[data-concierge-chat-target='log']")
  end
end
