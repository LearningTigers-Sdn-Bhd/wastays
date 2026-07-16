# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::DateWindow do
  let(:business_date) { Date.new(2026, 7, 16) }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur", accounting_business_date: business_date) }
  let(:now) { Time.find_zone!("Kuala Lumpur").local(2026, 7, 17, 1, 30) }

  it "uses the accounting business date and safe range defaults" do
    window = described_class.new(hotel:, start_date: "invalid", days: 13, view_mode: "unknown", now:)

    expect(window.today).to eq(Date.new(2026, 7, 17))
    expect(window.operational_date).to eq(business_date)
    expect(window.start_date).to eq(business_date)
    expect(window.end_date).to eq(Date.new(2026, 7, 30))
    expect(window.days).to eq(14)
    expect(window.view_mode).to eq(:timeline)
  end

  it "forces Room View to one selected operational day" do
    window = described_class.new(hotel:, start_date: "2026-07-20", days: 30, view_mode: :rooms, now:)

    expect(window.dates).to eq([ Date.new(2026, 7, 20) ])
    expect(window.end_date).to eq(Date.new(2026, 7, 21))
  end

  it "navigates by the complete visible range" do
    window = described_class.new(hotel:, start_date: "2026-07-16", days: 7, now:)

    expect(window.previous.start_date).to eq(Date.new(2026, 7, 9))
    expect(window.next.start_date).to eq(Date.new(2026, 7, 23))
    expect(window.previous.operational_date).to eq(business_date)
  end

  it "uses exclusive overlap and clipping boundaries" do
    window = described_class.new(hotel:, start_date: "2026-07-16", days: 7, now:)

    expect(window).to be_overlap(Date.new(2026, 7, 15), Date.new(2026, 7, 17))
    expect(window).not_to be_overlap(Date.new(2026, 7, 9), Date.new(2026, 7, 16))
    expect(window.clip(Date.new(2026, 7, 14), Date.new(2026, 7, 25))).to eq([ Date.new(2026, 7, 16), Date.new(2026, 7, 23) ])
  end

  it "converts booking centres and full-day boundaries into one-based tracks" do
    window = described_class.new(hotel:, start_date: "2026-07-16", days: 7, now:)

    one_night = window.booking_tracks(Date.new(2026, 7, 16), Date.new(2026, 7, 17))
    clipped = window.booking_tracks(Date.new(2026, 7, 14), Date.new(2026, 7, 24))
    full_day = window.full_day_tracks(Date.new(2026, 7, 17), Date.new(2026, 7, 19))

    expect(one_night.to_h).to include(start_track: 2, end_track: 4, clipped_left: false, clipped_right: false)
    expect(clipped.to_h).to include(start_track: 1, end_track: 15, clipped_left: true, clipped_right: true)
    expect(full_day.to_h).to include(start_track: 3, end_track: 7)
  end

  it "gives same-day stays a minimal positive width" do
    window = described_class.new(hotel:, start_date: "2026-07-16", days: 7, now:)

    same_day = window.booking_tracks(Date.new(2026, 7, 18), Date.new(2026, 7, 18))

    expect(same_day.to_h).to include(start_track: 6, end_track: 7, clipped_left: false, clipped_right: false)
  end
end
