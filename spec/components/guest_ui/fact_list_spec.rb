# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::FactList, type: :component do
  it "shows each fact as a term and its value" do
    render_inline(described_class.new(facts: [ [ "Check-in from", "15:00" ], [ "Check-out by", "12:00" ] ]))

    expect(page).to have_css("dl.guest-fact-list dt", text: "Check-in from")
    expect(page).to have_css("dl.guest-fact-list dd", text: "15:00")
    expect(page).to have_css("dl.guest-fact-list > div", count: 2)
  end

  it "leaves out a fact with no value" do
    render_inline(described_class.new(facts: [ [ "Price", nil ], [ "Type", "Valet" ] ]))

    expect(page).to have_no_text("Price")
    expect(page).to have_css("dd", text: "Valet")
  end

  it "draws nothing when no fact has a value" do
    render_inline(described_class.new(facts: [ [ "Price", "" ] ]))

    expect(page).to have_no_css("dl")
  end

  it "marks a value the guest copies" do
    render_inline(described_class.new(facts: [ described_class.fact("Password", "aurora2026", copy: true) ]))

    expect(page).to have_css("dd[data-copy='true']", text: "aurora2026")
  end

  it "puts a decorative icon before a label, one fact a row" do
    render_inline(described_class.new(columns: 1, facts: [ described_class.fact("Pets", "Not allowed", icon: "paw-print") ]))

    expect(page).to have_css("dl.guest-fact-list[data-columns='1']")
    expect(page).to have_css(".guest-fact-list__fact--icon svg.guest-fact-list__icon[aria-hidden='true']")
    expect(page).to have_css("dt", text: "Pets")
  end
end
