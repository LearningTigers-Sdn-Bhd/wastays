require "rails_helper"

RSpec.describe HotelPortal::Requests::DateWindow, frozen_time: Time.zone.local(2026, 8, 15, 12) do
  let(:hotel) { create(:hotel) }

  def window(**options)
    described_class.new(hotel: hotel, **options)
  end

  describe "reaching back from the anchor" do
    it "shows the anchor day and the days behind it" do
      subject = window(anchor_date: "2026-07-31", days: 7)

      expect(subject.anchor_date).to eq(Date.new(2026, 7, 31))
      expect(subject.start_date).to eq(Date.new(2026, 7, 25))
      expect(subject.end_date).to eq(Date.new(2026, 8, 1))
    end

    it "includes the anchor day itself" do
      subject = window(anchor_date: "2026-07-31", days: 7)

      expect(subject).to include(Date.new(2026, 7, 31))
      expect(subject).to include(Date.new(2026, 7, 25))
      expect(subject).not_to include(Date.new(2026, 7, 24))
      expect(subject).not_to include(Date.new(2026, 8, 1))
    end

    described_class::ALLOWED_DAYS.each do |days|
      it "spans #{days} days when asked for #{days}" do
        subject = window(anchor_date: "2026-07-31", days: days)

        expect(subject.days).to eq(days)
        expect((subject.start_date...subject.end_date).count).to eq(days)
      end
    end
  end

  describe "falling back" do
    it "defaults to a week" do
      expect(window.days).to eq(7)
    end

    it "refuses a range it does not offer" do
      expect(window(days: 14).days).to eq(described_class::DEFAULT_DAYS)
      expect(window(days: "everything").days).to eq(described_class::DEFAULT_DAYS)
    end

    it "anchors on today in the hotel's zone when no date is given" do
      expect(window.anchor_date).to eq(Time.current.in_time_zone(hotel.hotel_time_zone).to_date)
      expect(window).to be_today
    end

    it "anchors on today when the date cannot be read" do
      expect(window(anchor_date: "31/07/2026").anchor_date).to eq(window.today)
      expect(window(anchor_date: "").anchor_date).to eq(window.today)
    end

    # A window reaching back from a business date still waiting on a night audit
    # would end before the requests arriving right now.
    it "reaches back from the wall clock even when the business date lags behind it" do
      allow(hotel).to receive(:current_business_date).and_return(Date.current - 3)

      subject = window

      expect(subject.anchor_date).to eq(Time.current.in_time_zone(hotel.hotel_time_zone).to_date)
      expect(subject.range).to cover(Time.current)
    end

    it "accepts a date object as readily as a string" do
      expect(window(anchor_date: Date.new(2026, 7, 31)).anchor_date).to eq(Date.new(2026, 7, 31))
    end
  end

  describe "stepping" do
    it "steps back by its own range" do
      subject = window(anchor_date: "2026-07-31", days: 7).previous

      expect(subject.anchor_date).to eq(Date.new(2026, 7, 24))
      expect(subject.days).to eq(7)
    end

    it "steps forward by its own range" do
      subject = window(anchor_date: "2026-07-31", days: 5).next

      expect(subject.anchor_date).to eq(Date.new(2026, 8, 5))
      expect(subject.days).to eq(5)
    end

    it "returns to where it started" do
      subject = window(anchor_date: "2026-07-31", days: 3)

      expect(subject.previous.next.anchor_date).to eq(subject.anchor_date)
    end


    it "leaves the window it stepped from alone" do
      subject = window(anchor_date: "2026-07-31", days: 7)
      subject.previous

      expect(subject.anchor_date).to eq(Date.new(2026, 7, 31))
      expect(subject).to be_frozen
    end
  end

  # requested_at and completed_at are timestamps. Read the window as dates and
  # every hotel off UTC gets the wrong day at the boundary.
  describe "the times it compares against" do
    let(:hotel) { create(:hotel, time_zone: "Asia/Kuala_Lumpur") }

    it "opens and closes at midnight in the hotel's own zone" do
      subject = window(anchor_date: "2026-07-31", days: 7)

      expect(subject.starts_at).to eq(Time.find_zone!("Asia/Kuala_Lumpur").local(2026, 7, 25))
      expect(subject.ends_at).to eq(Time.find_zone!("Asia/Kuala_Lumpur").local(2026, 8, 1))
      expect(subject.starts_at.utc_offset).to eq(8.hours)
    end

    it "keeps the anchor's last local hour inside the window" do
      subject = window(anchor_date: "2026-07-31", days: 7)
      last_local_moment = Time.find_zone!("Asia/Kuala_Lumpur").local(2026, 7, 31, 23, 59, 59)

      expect(subject.range).to cover(last_local_moment)
    end

    it "keeps the hour before the window out of it" do
      subject = window(anchor_date: "2026-07-31", days: 7)
      just_before = Time.find_zone!("Asia/Kuala_Lumpur").local(2026, 7, 24, 23, 59, 59)

      expect(subject.range).not_to cover(just_before)
    end
  end

  it "travels in a link as its anchor and its range" do
    subject = window(anchor_date: "2026-07-31", days: 5)

    expect(subject.query_params).to eq(date: "2026-07-31", days: 5)
  end
end
