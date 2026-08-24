# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::Log, type: :component do
  let(:conversation) { build_stubbed(:conversation) }

  it "renders the thread in order, announced as it grows" do
    messages = [
      build_stubbed(:prospect_message, sender_role: "guest", body: "Do you have parking?"),
      build_stubbed(:prospect_message, sender_role: "bot", body: "We do, it is free.")
    ]

    render_inline(described_class.new(conversation: conversation, messages: messages))

    expect(page).to have_css("ol[role='log'][aria-live='polite'][aria-label='Conversation']")
    expect(page.all("li > div").map(&:text)).to eq([ "Do you have parking?", "We do, it is free." ])
  end

  # The id ProspectMessage broadcasts at. It has to exist before there is
  # anything in it, or the first live message has nowhere to land.
  it "renders the append anchor even with nothing in it" do
    render_inline(described_class.new(conversation: conversation, messages: []))

    expect(page).to have_css("ol##{described_class.dom_id_for(conversation)}")
  end

  it "groups what one author said in a row into a single run" do
    messages = [
      build_stubbed(:prospect_message, sender_role: "guest", body: "Do you have parking?"),
      build_stubbed(:prospect_message, sender_role: "bot", body: "We do."),
      build_stubbed(:prospect_message, sender_role: "bot", body: "It is free for guests."),
      build_stubbed(:prospect_message, sender_role: "guest", body: "Thanks!")
    ]

    render_inline(described_class.new(conversation: conversation, messages: messages))

    runs = page.all("li").map { |item| [ item["data-run-start"], item["data-run-end"] ] }
    expect(runs).to eq([ %w[true true], %w[true false], %w[false true], %w[true true] ])
    expect(page).to have_text("Assistant", count: 1)
  end

  it "keeps two different people apart even when both are staff" do
    farah = build_stubbed(:user, name: "Farah")
    amir = build_stubbed(:user, name: "Amir")
    messages = [
      build_stubbed(:prospect_message, sender_role: "staff", sender_user: farah, body: "Checking now."),
      build_stubbed(:prospect_message, sender_role: "staff", sender_user: amir, body: "Room 12 is ready.")
    ]

    render_inline(described_class.new(conversation: conversation, messages: messages))

    expect(page.all("li").map { |item| item["data-run-start"] }).to eq(%w[true true])
    expect(page).to have_text("Farah")
    expect(page).to have_text("Amir")
  end

  it "leaves a system line standing on its own between two bot replies" do
    messages = [
      build_stubbed(:prospect_message, sender_role: "bot", body: "One moment."),
      build_stubbed(:prospect_message, sender_role: "system", body: "Farah joined the chat"),
      build_stubbed(:prospect_message, sender_role: "bot", body: "Still here.")
    ]

    render_inline(described_class.new(conversation: conversation, messages: messages))

    expect(page.all("li").map { |item| item["data-run-end"] }).to eq(%w[true true true])
  end

  it "wires the scroll target the chat controller looks for" do
    render_inline(described_class.new(conversation: conversation, messages: []))

    expect(page).to have_css("ol[data-concierge-chat-target='log']")
  end
end
