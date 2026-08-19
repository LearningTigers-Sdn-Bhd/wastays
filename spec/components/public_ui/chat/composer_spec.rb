# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Chat::Composer, type: :component do
  it "posts a labelled message field to the given url" do
    render_inline(described_class.new(url: "/concierge/aurora/chat"))

    expect(page).to have_css("form.public-chat__composer[action='/concierge/aurora/chat'][method='post']")
    expect(page).to have_css("label.public-chat__label[for='message']", text: "Your message")
    expect(page).to have_css("textarea#message.public-chat__input[required][placeholder='Type your message...'][data-concierge-chat-target='input']")
    expect(page).to have_css("input.public-chat__send[value='Send →']")
  end

  it "lets the caller rename the field, the labels and the button" do
    render_inline(described_class.new(
      url: "/concierge/aurora/chat", param: :reply, label: "Reply",
      placeholder: "Write back...", submit_label: "Reply →", rows: 5
    ))

    expect(page).to have_css("textarea#reply[name='reply'][rows='5'][placeholder='Write back...']")
    expect(page).to have_css("label[for='reply']", text: "Reply")
    expect(page).to have_css("input[value='Reply →']")
  end
end
