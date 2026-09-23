# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Disclosure, type: :component do
  it "is a native details element with the title as its summary" do
    render_inline(described_class.new(title: "Is breakfast included?")) { "Yes, from 7 AM." }

    expect(page).to have_css("details.guest-disclosure:not([open]) > summary", text: "Is breakfast included?")
    expect(page).to have_css(".guest-disclosure__body", text: "Yes, from 7 AM.", visible: :all)
    expect(page).to have_css(".guest-disclosure__chevron[aria-hidden='true']")
  end

  it "can start open" do
    render_inline(described_class.new(title: "Parking", open: true)) { "On-site" }

    expect(page).to have_css("details.guest-disclosure[open]")
  end

  it "draws nothing without content" do
    render_inline(described_class.new(title: "Parking"))

    expect(page).to have_no_css("details")
  end
end
