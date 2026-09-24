# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::AmenityCard, type: :component do
  it "shows the facts at once, each with a spoken term" do
    render_inline(described_class.new(name: "Swimming pool", icon: "waves-ladder", category: "Outdoors",
                                      location: "Level 1", hours: "7:00 AM to 9:00 PM", price: "Free"))

    expect(page).to have_css("article.guest-amenity h3", text: "Swimming pool")
    expect(page).to have_css(".guest-amenity__meta", text: "Outdoors")
    expect(page).to have_css("dt .sr-only", text: "Hours")
    expect(page).to have_css("dd", text: "7:00 AM to 9:00 PM")
    expect(page).to have_css(".guest-guide-icon svg[aria-hidden='true']")
    expect(page).to have_no_css(".guest-amenity__badge")
  end

  it "says Book ahead in words, with how to book" do
    render_inline(described_class.new(name: "Spa", book_ahead: true, booking: "Call extension 5."))

    expect(page).to have_css(".guest-amenity__meta .guest-amenity__badge", text: "Book ahead")
    expect(page).to have_text("How to book: Call extension 5.")
  end

  it "leaves out a booking line when booking is not needed" do
    render_inline(described_class.new(name: "Gym", booking: "Old instructions"))

    expect(page).to have_no_text("How to book")
  end

  it "sends the guest to the front desk when staff wrote nothing" do
    render_inline(described_class.new(name: "Laundry"))

    expect(page).to have_no_css("dl")
    expect(page).to have_text("Ask the front desk for details.")
  end

  it "picks an icon from the amenity, then from its category" do
    expect(described_class.icon_for(slug: "swimming_pool")).to eq("waves-ladder")
    expect(described_class.icon_for(slug: "karaoke", category: "Activities")).to eq("ticket")
    expect(described_class.icon_for(slug: "unknown")).to eq("sparkles")
    expect(described_class.icon_for(slug: "barbecue_facilities", category: "Outdoors")).to eq("trees")
  end
end
