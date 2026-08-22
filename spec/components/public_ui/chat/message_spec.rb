# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Message, type: :component do
  let(:hotel) { build_stubbed(:hotel, name: "Aurora Crown Resort") }

  def message_for(sender_role, body: "Hello", **attributes)
    build_stubbed(:prospect_message, sender_role: sender_role, body: body, **attributes)
  end

  it "puts the guest's own words on their side, named as theirs" do
    render_inline(described_class.new(message: message_for("guest"), hotel: hotel))

    expect(page).to have_css("li.public-chat__message[data-side='guest'] .public-chat__author", text: "You")
    expect(page).to have_css(".public-chat__bubble", text: "Hello")
  end

  it "answers in the hotel's name when the bot replied" do
    render_inline(described_class.new(message: message_for("bot"), hotel: hotel))

    expect(page).to have_css("[data-side='hotel'] .public-chat__author", text: "Aurora Crown Resort")
  end

  it "names the person when staff replied" do
    user = build_stubbed(:user, name: "Farah")
    render_inline(described_class.new(message: message_for("staff", sender_user: user), hotel: hotel))

    expect(page).to have_css("[data-side='staff'] .public-chat__author", text: "Farah")
  end

  it "narrates a system line without attributing it to anyone" do
    render_inline(described_class.new(message: message_for("system", body: "A team member joined"), hotel: hotel))

    expect(page).to have_css("[data-side='system'] .public-chat__bubble", text: "A team member joined")
    expect(page).to have_no_css(".public-chat__author")
  end

  it "stands alone by default -- named, and carrying the tail" do
    render_inline(described_class.new(message: message_for("bot"), hotel: hotel))

    expect(page).to have_css("li[data-run-start='true'][data-run-end='true'] .public-chat__author")
  end

  it "drops the name when it continues what the same author was saying" do
    render_inline(described_class.new(message: message_for("bot"), hotel: hotel, first_in_run: false))

    expect(page).to have_css("li[data-run-start='false']")
    expect(page).to have_no_css(".public-chat__author")
  end

  it "gives up the tail when someone else speaks after it" do
    render_inline(described_class.new(message: message_for("bot"), hotel: hotel, last_in_run: false))

    expect(page).to have_css("li[data-run-end='false']")
  end

  it "carries a stable dom id so a live append can be addressed" do
    message = message_for("guest")

    render_inline(described_class.new(message: message, hotel: hotel))

    expect(page).to have_css("li##{ActionView::RecordIdentifier.dom_id(message)}")
  end

  # The bubble is whitespace-pre-wrap: template indentation around the body would
  # render as a literal indent on the guest's screen.
  it "renders the body without leading whitespace" do
    render_inline(described_class.new(message: message_for("bot", body: "Welcome!"), hotel: hotel))

    expect(page.find(".public-chat__bubble").native.to_html).to include(">Welcome!<")
  end
end
