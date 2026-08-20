# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Inbox::Message, type: :component do
  def message_for(sender_role, body: "Hello", **attributes)
    build_stubbed(:prospect_message, sender_role: sender_role, body: body, **attributes)
  end

  it "puts the guest's words on their side, named as the guest" do
    render_inline(described_class.new(message: message_for("guest")))

    expect(page).to have_css("li[data-side='guest']", text: "Guest")
    expect(page).to have_css("li[data-side='guest'] div", text: "Hello")
  end

  # The question a staff member is actually asking as they read down a thread.
  it "keeps a colleague's reply visibly apart from the assistant's" do
    farah = build_stubbed(:user, name: "Farah")

    render_inline(described_class.new(message: message_for("staff", sender_user: farah)))
    staff_bubble = page.find("li[data-side='staff'] div")[:class]

    render_inline(described_class.new(message: message_for("bot")))
    bot_bubble = page.find("li[data-side='bot'] div")[:class]

    expect(staff_bubble).not_to eq(bot_bubble)
  end

  it "names the person who replied, and the assistant when it answered" do
    farah = build_stubbed(:user, name: "Farah")

    render_inline(described_class.new(message: message_for("staff", sender_user: farah)))
    expect(page).to have_css("li[data-side='staff']", text: "Farah")

    render_inline(described_class.new(message: message_for("bot")))
    expect(page).to have_css("li[data-side='bot']", text: "Assistant")
  end

  # Narration about the conversation, not something the hotel said in it.
  it "stands a system line apart and attributes it to nobody" do
    render_inline(described_class.new(message: message_for("system", body: "Farah joined")))

    expect(page).to have_css("li[data-side='system']", text: "Farah joined")
    expect(page).to have_no_text("System")
  end

  it "stands alone by default -- named, and closing its run" do
    render_inline(described_class.new(message: message_for("bot")))

    expect(page).to have_css("li[data-run-start='true'][data-run-end='true']")
    expect(page).to have_text("Assistant")
  end

  it "drops the name when it continues what the same author was saying" do
    render_inline(described_class.new(message: message_for("bot"), first_in_run: false))

    expect(page).to have_css("li[data-run-start='false']")
    expect(page).to have_no_text("Assistant")
  end

  it "gives up the run end when someone speaks after it" do
    render_inline(described_class.new(message: message_for("bot"), last_in_run: false))

    expect(page).to have_css("li[data-run-end='false']")
  end

  it "carries a stable dom id so a live append can be addressed" do
    message = message_for("guest")

    render_inline(described_class.new(message: message))

    expect(page).to have_css("li##{ActionView::RecordIdentifier.dom_id(message)}")
  end

  it "times the message for a screen reader as well as the eye" do
    message = message_for("guest", sent_at: Time.zone.parse("2026-08-19 09:59"))

    render_inline(described_class.new(message: message))

    expect(page).to have_css("time[datetime='#{message.sent_at.iso8601}']")
  end

  describe "a reply that was rewritten for the guest" do
    it "keeps the English the assistant computed within reach" do
      message = message_for("bot", body: "Selamat datang!", source_body: "Welcome!")

      render_inline(described_class.new(message: message))

      expect(page).to have_text("Selamat datang!")
      expect(page).to have_text("Show original")
      expect(page).to have_text("Welcome!")
    end

    it "says nothing about an original on a reply nobody rewrote" do
      render_inline(described_class.new(message: message_for("bot", body: "Welcome!")))

      expect(page).to have_no_text("Show original")
    end
  end

  # The bubble is whitespace-pre-wrap: template indentation around the body would
  # render as a literal indent.
  it "renders the body without leading whitespace" do
    render_inline(described_class.new(message: message_for("bot", body: "Welcome!")))

    expect(page.find("li > div").native.to_html).to include(">Welcome!<")
  end
end
