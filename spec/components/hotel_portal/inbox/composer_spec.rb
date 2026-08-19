# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::Composer, type: :component do
  # to_param is the immutable 5-char code, so a hotel without one has no URL.
  let(:hotel) { build_stubbed(:hotel, unique_id: "AURCR") }

  it "offers the box where a reply actually arrives" do
    conversation = build_stubbed(:conversation, hotel: hotel, channel: "web", status: "open")

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_css("textarea")
    expect(page).to have_button("Send reply")
  end

  # A stored reply the guest never sees is worse than no box at all -- staff
  # believe they have answered.
  it "withholds the box on a channel with no outbound route" do
    conversation = build_stubbed(:conversation, hotel: hotel, channel: "whatsapp", status: "open")

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_no_button("Send reply")
    expect(page).to have_text("not switched on yet")
  end

  it "asks for a reopen instead of a reply once the thread is closed" do
    conversation = build_stubbed(:conversation, hotel: hotel, channel: "web", status: "closed")

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_no_button("Send reply")
    expect(page).to have_text("Reopen it to reply")
  end

  it "carries a stable id so closing the thread elsewhere can replace it" do
    conversation = build_stubbed(:conversation, hotel: hotel, channel: "web", status: "open")

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_css("##{described_class.dom_id_for(conversation)}")
  end
end
