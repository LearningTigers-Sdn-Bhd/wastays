# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::BookingCard, type: :component do
  let(:badge) { GuestUI::StatusBadge.new(label: "Confirmed", tone: :info, icon: "calendar-check") }

  def card(**options)
    described_class.new(href: "/guest/bookings/1", property: "Aurora Crown", badge:,
                        dates: "12 Oct – 15 Oct 2026", detail: "3 nights · 2 adults",
                        reference: "AUR-RES-2026-00042", code: "WS-8KD2QX", paid: "MYR 780.00", **options)
  end

  it "is one link holding the stay, its status, and the money in its footer" do
    render_inline(card(outstanding: "MYR 120.00", owing: true))

    link = page.find("a.guest-booking-card[href='/guest/bookings/1']")
    expect(link).to have_css(".guest-booking-card__property", text: "Aurora Crown")
    expect(link).to have_css(".guest-status-badge", text: "Confirmed")
    expect(link).to have_text("12 Oct – 15 Oct 2026")
    expect(link).to have_css(".guest-booking-card__body dd", text: "AUR-RES-2026-00042")
    expect(link).to have_css(".guest-booking-card__body dd", text: "WS-8KD2QX")
    amounts = link.all(".guest-booking-card__footer .guest-booking-card__amount").map { |row| row.text.squish }
    expect(amounts).to eq([ "Total spent MYR 780.00", "Outstanding MYR 120.00" ])
    expect(link).to have_css(".guest-booking-card__amount[data-owing='true']")
    expect(link).to have_no_css("a, button")
  end

  it "leaves the outstanding line out when there is none to show" do
    render_inline(card)

    expect(page).to have_css(".guest-booking-card__amount", count: 1)
  end
end
