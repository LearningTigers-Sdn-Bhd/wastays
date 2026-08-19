# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Composer, type: :component do
  it "posts a message field and a send button to the given url" do
    render_inline(described_class.new(url: "/concierge/aurora/chat"))

    expect(page).to have_css("form.public-chat__composer[action='/concierge/aurora/chat'][method='post']")
    expect(page).to have_css("textarea#message.public-chat__input[required][rows='1'][placeholder='Type your message...'][data-concierge-chat-target='input']")
    expect(page).to have_css("button.public-chat__send[type='submit'][aria-label='Send']")
  end

  # The box sits under the thread with nothing else it could be for, so the
  # label is read out rather than drawn.
  it "keeps the label for screen readers only" do
    render_inline(described_class.new(url: "/concierge/aurora/chat"))

    expect(page).to have_css("label.sr-only[for='message']", text: "Your message")
    expect(page).to have_no_css(".public-chat__label")
  end

  it "grows with what is typed, and sends on Enter" do
    render_inline(described_class.new(url: "/concierge/aurora/chat"))

    actions = page.find("textarea")["data-action"]
    expect(actions).to include("input->concierge-chat#growInput")
    expect(actions).to include("keydown->concierge-chat#onInputKeydown")
  end

  # The reply to a send appends rather than replaces, so something has to empty
  # the box afterwards.
  it "asks the chat controller to empty it once a send lands" do
    render_inline(described_class.new(url: "/concierge/aurora/chat"))

    expect(page).to have_css("form[data-action='turbo:submit-end->concierge-chat#onSubmitEnd']")
  end

  it "lets the caller rename the field and its labels" do
    render_inline(described_class.new(
      url: "/concierge/aurora/chat", param: :reply, label: "Reply",
      placeholder: "Write back...", submit_label: "Send reply", rows: 3
    ))

    expect(page).to have_css("textarea#reply[name='reply'][rows='3'][placeholder='Write back...']")
    expect(page).to have_css("label[for='reply']", text: "Reply")
    expect(page).to have_css("button[aria-label='Send reply']")
  end
end
