# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::BookingCard, type: :component do
  let(:badge) { GuestUI::StatusBadge.new(label: "Confirmed", tone: :info, icon: "calendar-check") }

  it "is one link holding the stay, its status, and both numbers" do
    render_inline(described_class.new(href: "/guest/bookings/1", property: "Aurora Crown", badge:,
                                      dates: "12 Oct – 15 Oct 2026", detail: "3 nights · 2 adults",
                                      reference: "AUR-RES-2026-00042", code: "WS-8KD2QX"))

    card = page.find("a.guest-booking-card[href='/guest/bookings/1']")
    expect(card).to have_css(".guest-booking-card__property", text: "Aurora Crown")
    expect(card).to have_css(".guest-status-badge", text: "Confirmed")
    expect(card).to have_text("12 Oct – 15 Oct 2026")
    expect(card).to have_css("dd", text: "AUR-RES-2026-00042")
    expect(card).to have_css("dd", text: "WS-8KD2QX")
    expect(card).to have_no_css("a, button")
  end
end
