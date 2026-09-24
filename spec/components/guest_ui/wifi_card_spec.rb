# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::WifiCard, type: :component do
  it "shows the name and the password, each with a Copy button" do
    render_inline(described_class.new(label: "Main WiFi", ssid: "Aurora-5g", password: "secret1", primary: true))

    expect(page).to have_css("article.guest-wifi[data-controller='clipboard'] h3", text: "Main WiFi")
    expect(page).to have_css(".guest-guide-card__subtitle", text: "Main network")
    expect(page).to have_css("button[aria-label='Copy network name'][data-clipboard-text-value='Aurora-5g']", text: "Copy")
    expect(page).to have_css("button[aria-label='Copy password'][data-clipboard-text-value='secret1']")
    expect(page).to have_css("[role='status'][data-clipboard-target='status']")
  end

  it "says an open network needs no password, and offers nothing to copy for it" do
    render_inline(described_class.new(label: "Lobby", ssid: "Lobby"))

    expect(page).to have_text("No password needed")
    expect(page).to have_no_css("button[aria-label='Copy password']")
  end

  it "turns numbered lines into steps" do
    render_inline(described_class.new(label: "Main", ssid: "A", password: "b",
                                      instructions: "1. Open settings.\n2. Pick the network."))

    expect(page).to have_css("ol.guest-wifi__steps li", count: 2)
    expect(page).to have_css("li", text: /\AOpen settings\.\z/)
  end

  it "offers a join code for a second device" do
    render_inline(described_class.new(label: "Main", ssid: "A;B", password: "p:1"))

    expect(page).to have_css("details summary", text: "Join from another device")
    expect(page).to have_css("details img[alt='Code to join A;B'][src^='data:image/svg+xml;base64,']", visible: :all)
  end

  it "escapes the join code the way a phone camera reads it" do
    card = described_class.new(label: "Main", ssid: "A;B", password: "p:1")

    expect(card.send(:join_payload)).to eq('WIFI:T:WPA;S:A\;B;P:p\:1;;')
    expect(described_class.new(label: "Open", ssid: "Lobby").send(:join_payload)).to eq("WIFI:T:nopass;S:Lobby;;")
  end
end
