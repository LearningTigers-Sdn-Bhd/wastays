# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::PaymentSchedule do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 72, time_zone: "Asia/Kuala_Lumpur") }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:now) { Time.zone.parse("2026-09-18 09:00") }

  def schedule(check_in:, total: 1000, relationship: self.relationship)
    booking = build(:booking, hotel: hotel, hotel_corporate_account: relationship, total_amount: total,
                              check_in: check_in, check_out: check_in + 2.days)
    described_class.for(booking: booking, from: now)
  end

  it "asks for the deposit within the hold and the balance 30 days before arrival" do
    stages = schedule(check_in: now + 60.days)

    expect(stages.map(&:kind)).to eq(%w[deposit balance])
    expect(stages.map(&:amount)).to eq([ 500, 500 ])
    expect(stages.first.due_at).to eq(now + 72.hours)
    kl = Time.find_zone("Asia/Kuala_Lumpur")
    arrival_day = (now + 60.days).in_time_zone(kl).to_date
    expect(stages.last.due_at).to eq(kl.local(arrival_day.year, arrival_day.month, arrival_day.day).end_of_day - 30.days)
  end

  it "uses the hotel's own deposit percentage and lead time" do
    hotel.update!(agent_deposit_percentage: 30, agent_full_payment_days_before_arrival: 14)

    stages = schedule(check_in: now + 60.days)

    expect(stages.map(&:amount)).to eq([ 300, 700 ])
    expect(stages.last.due_at.to_date).to eq((now + 60.days - 14.days).to_date)
  end

  it "rounds the deposit up so it is never below the share promised" do
    stages = schedule(check_in: now + 60.days, total: 100.01)

    expect(stages.first.amount).to eq(BigDecimal("50.01"))
    expect(stages.sum(&:amount)).to eq(BigDecimal("100.01"))
  end

  # Arrival is 20 days out, so the 30-day mark has already passed: only the
  # deposit deadline can still be met, and the whole amount is due then.
  it "asks for everything within the hold when arrival is closer than the full-payment lead time" do
    stages = schedule(check_in: now + 20.days)

    expect(stages.size).to eq(1)
    expect(stages.first).to have_attributes(kind: "full", amount: 1000, due_at: now + 72.hours)
  end

  # 33 days out: the hold ends at 09:00 on day 3 and the balance would be due at
  # the end of that same day. One payment, not two on one day.
  it "asks for everything within the hold when the balance would fall on the deposit's day" do
    stages = schedule(check_in: now + 33.days)

    expect(stages.map(&:kind)).to eq(%w[full])
  end

  it "keeps two stages when the balance falls a day after the hold ends" do
    stages = schedule(check_in: now + 34.days)

    expect(stages.map(&:kind)).to eq(%w[deposit balance])
  end

  it "is a single full stage at 100%" do
    hotel.update!(agent_deposit_percentage: 100)

    expect(schedule(check_in: now + 60.days).map(&:kind)).to eq(%w[full])
  end

  it "floors the only deadline at arrival for a booking made the day before" do
    check_in = now + 6.hours
    stages = schedule(check_in: check_in)

    expect(stages.size).to eq(1)
    expect(stages.first.due_at).to eq(check_in)
  end

  it "carries no schedule for a direct-bill agency" do
    direct = create(:hotel_corporate_account, :direct_bill, hotel: hotel, account_type: "travel_agent")

    expect(schedule(check_in: now + 60.days, relationship: direct)).to be_empty
  end

  it "carries no schedule for a booking with no agency" do
    expect(schedule(check_in: now + 60.days, relationship: nil)).to be_empty
  end

  it "carries no schedule for a free booking" do
    expect(schedule(check_in: now + 60.days, total: 0)).to be_empty
  end
end
