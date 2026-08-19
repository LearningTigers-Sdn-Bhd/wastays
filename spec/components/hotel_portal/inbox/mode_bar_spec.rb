# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::ModeBar, type: :component do
  # to_param is the immutable 5-char code, so a hotel without one has no URL.
  let(:hotel) { build_stubbed(:hotel, unique_id: "AURCR") }

  def render_bar(conversation, assistant_ready: true)
    allow(hotel).to receive(:ai_concierge_ready?).and_return(assistant_ready)
    render_inline(described_class.new(conversation: conversation, hotel: hotel))
  end

  it "offers the handover while the assistant is answering" do
    render_bar(build_stubbed(:conversation, hotel: hotel, mode: "bot", status: "open"))

    expect(page).to have_button("Take over")
    expect(page).to have_text("The assistant is answering")
  end

  it "offers the way back once a person is holding it" do
    render_bar(build_stubbed(:conversation, hotel: hotel, mode: "human", status: "open"))

    expect(page).to have_button("Return to assistant")
    expect(page).to have_text("The assistant stays quiet")
  end

  # Offering to hand a thread back to an assistant the hotel has not switched on
  # is a button that can only fail.
  it "withholds the way back when the hotel has no assistant" do
    render_bar(build_stubbed(:conversation, hotel: hotel, mode: "human", status: "open"), assistant_ready: false)

    expect(page).to have_no_button("Return to assistant")
  end

  it "swaps closing for reopening once the conversation is closed" do
    render_bar(build_stubbed(:conversation, hotel: hotel, mode: "bot", status: "closed"))

    expect(page).to have_button("Reopen")
    expect(page).to have_no_button("Close")
    expect(page).to have_no_button("Take over")
  end

  # Nothing here may change a conversation on a crawler's GET.
  it "puts every move behind a non-GET form" do
    render_bar(build_stubbed(:conversation, hotel: hotel, mode: "bot", status: "open"))

    expect(page).to have_css("form[method='post']", minimum: 1)
    expect(page).to have_no_css("form[method='get']")
  end

  it "carries a stable id so a takeover elsewhere can replace it" do
    conversation = build_stubbed(:conversation, hotel: hotel, mode: "bot", status: "open")

    render_bar(conversation)

    expect(page).to have_css("##{described_class.dom_id_for(conversation)}")
  end
end
