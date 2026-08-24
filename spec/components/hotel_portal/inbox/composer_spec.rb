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
    expect(page).to have_text("You cannot reply to WhatsApp here yet")
    expect(page).to have_text("No WhatsApp relay is connected")
  end

  # A lapsed window is not the same refusal as a channel with no route out:
  # nothing is missing and nothing needs connecting, so saying "not yet" would
  # send a reader looking for a setting that would not help them.
  it "says the clock ran out rather than that the channel is unsupported" do
    hotel = create(:hotel)
    create(:webhook_endpoint, hotel: hotel, event_types: [ Concierge::DeliverStaffReply::EVENT ])
    conversation = create(
      :conversation, :whatsapp, :window_lapsed,
      hotel: hotel, prospect: create(:prospect, hotel: hotel, phone_number: "+60123456789")
    )

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_no_button("Send reply")
    expect(page).to have_text("24-hour reply window on this thread has closed")
    expect(page).to have_no_text("You cannot reply to WhatsApp here yet")
  end

  it "tells a WhatsApp writer how long they still have" do
    hotel = create(:hotel)
    create(:webhook_endpoint, hotel: hotel, event_types: [ Concierge::DeliverStaffReply::EVENT ])
    conversation = create(
      :conversation, :whatsapp,
      hotel: hotel, prospect: create(:prospect, hotel: hotel, phone_number: "+60123456789"),
      last_guest_message_at: 6.hours.ago - 30.minutes
    )

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_button("Send reply")
    expect(page).to have_text("Sent to the guest on WhatsApp. 17h left to reply.")
  end

  it "leaves the web note alone, since that chat has no window" do
    conversation = build_stubbed(:conversation, hotel: hotel, channel: "web", status: "open")

    render_inline(described_class.new(conversation: conversation, hotel: hotel))

    expect(page).to have_text("straight away")
    expect(page).to have_no_text("to reply.")
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
