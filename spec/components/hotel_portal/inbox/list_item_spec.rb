# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::ListItem, type: :component do
  # to_param is the immutable 5-char code, so a hotel without one has no URL.
  let(:hotel) { build_stubbed(:hotel, unique_id: "AURCR") }
  let(:conversation) { build_stubbed(:conversation, hotel: hotel, channel: "web", mode: "bot", status: "open") }

  it "carries a stable id so the inbox can refresh the row in place" do
    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_css("li##{described_class.dom_id_for(conversation)}")
  end

  # Which thread a reader has open is the one thing on this list that is true
  # for them and false for everybody else, so it lives on the row -- the part a
  # broadcast updating the row's contents does not touch.
  it "marks the open thread on the row, not on what a broadcast replaces" do
    render_inline(described_class.new(conversation: conversation, hotel: hotel, selected: true))

    expect(page).to have_css("li[aria-current='true'].bg-muted")
    expect(page).to have_no_css("a[aria-current]")
  end

  it "leaves an unopened row unmarked" do
    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_no_css("li[aria-current]")
    expect(page).to have_no_css("li.bg-muted")
  end

  it "holds the row's contents" do
    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_css("li > a[data-turbo-frame='conversation_thread']")
  end
end
