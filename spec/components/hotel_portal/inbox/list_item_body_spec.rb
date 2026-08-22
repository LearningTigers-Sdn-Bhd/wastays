# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::ListItemBody, type: :component do
  # to_param is the immutable 5-char code, so a hotel without one has no URL.
  let(:hotel) { build_stubbed(:hotel, unique_id: "AURCR") }
  let(:prospect) { build_stubbed(:prospect, hotel: hotel, name: "Aisyah Rahman") }
  let(:conversation) { build_stubbed(:conversation, hotel: hotel, prospect: prospect, channel: "web", mode: "bot", status: "open") }

  def render_body(unread: 0)
    presenter = HotelPortal::ConversationPresenter.new(conversation, view: vc_test_controller.view_context)
    allow(presenter).to receive(:unread_count).and_return(unread)
    allow_any_instance_of(HotelPortal::ConversationsHelper).to receive(:conversation_presenter).and_return(presenter)

    render_inline(described_class.new(conversation: conversation, hotel: hotel))
  end

  it "names the guest and links to the thread inside the frame" do
    render_body

    expect(page).to have_link("Aisyah Rahman", href: "/hotel/AURCR/conversations/#{conversation.id}")
    expect(page).to have_css("a[data-turbo-frame='conversation_thread']")
  end

  # Never colour or position alone (DESIGN.md §10) -- the dot is decorative and
  # the count is what a screen reader hears.
  it "says how many messages are unread, not just marks the row" do
    render_body(unread: 3)

    expect(page).to have_css("span[aria-hidden='true'].rounded-full")
    expect(page).to have_css("span.sr-only", text: "3 unread messages")
  end

  it "leaves an answered row unmarked" do
    render_body(unread: 0)

    expect(page).to have_no_css("span.sr-only", text: "unread")
  end

  describe "a thread the guest is not writing in English" do
    it "says which language, before anyone opens it" do
      conversation.language = "ms"

      render_body

      expect(page).to have_text("Malay")
    end

    it "falls back to the code for a language it cannot name" do
      conversation.language = "pt"

      render_body

      expect(page).to have_text("PT")
    end

    it "says nothing on an English thread" do
      render_body

      expect(page).to have_no_text("Malay")
    end
  end

  it "says who is holding the thread" do
    render_body

    expect(page).to have_text("Bot handling")
  end

  # WhatsApp stops carrying a reply 24 hours after the guest last wrote, and a
  # reader scanning the list should see which threads are running out before
  # they open one and start typing.
  describe "the reply window" do
    it "shows how long is left on a WhatsApp thread" do
      conversation.channel = "whatsapp"
      conversation.last_guest_message_at = 6.hours.ago - 30.minutes

      render_body

      expect(page).to have_text("17h left")
    end

    it "says nothing on the web chat, which has no window" do
      conversation.last_guest_message_at = 3.years.ago

      render_body

      expect(page).to have_no_text("left")
    end
  end
end
