# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::Thread, type: :component do
  # to_param is the immutable 5-char code, so a hotel without one has no URL.
  let(:hotel) { build_stubbed(:hotel, unique_id: "AURCR") }
  let(:conversation) { build_stubbed(:conversation, hotel: hotel, channel: "web", mode: "bot", status: "open") }

  before { allow(hotel).to receive(:ai_concierge_ready?).and_return(true) }

  def render_thread(messages: [])
    render_inline(described_class.new(conversation: conversation, messages: messages, hotel: hotel))
  end

  it "puts the three parts of a conversation in one card" do
    render_thread(messages: [ build_stubbed(:prospect_message, sender_role: "guest", body: "Any parking?") ])

    expect(page).to have_css("ol##{HotelPortal::Inbox::Log.dom_id_for(conversation)}")
    expect(page).to have_css("##{HotelPortal::Inbox::ModeBar.dom_id_for(conversation)}")
    expect(page).to have_css("##{HotelPortal::Inbox::Composer.dom_id_for(conversation)}")
    expect(page).to have_text("Any parking?")
  end

  it "heads the card with who the conversation is with" do
    render_thread

    expect(page).to have_css("h2", text: conversation.prospect.name.presence || "Unnamed guest")
  end

  # The card is exactly as tall as its pane: the header, mode bar and composer
  # hold their size and only the thread scrolls, or the composer gets pushed off
  # the bottom by a long conversation.
  it "holds its height and scrolls only the thread" do
    render_thread

    expect(page).to have_css("div.h-full.flex-col")
    expect(page).to have_css(".panel-scroll-area .panel-scroll-area__viewport")
    expect(page).to have_css("##{HotelPortal::Inbox::Composer.dom_id_for(conversation)}.shrink-0")
  end

  it "hands the card to the chat controller that keeps the newest message in view" do
    render_thread

    expect(page).to have_css("[data-controller~='concierge-chat']")
  end
end
