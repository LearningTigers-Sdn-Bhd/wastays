# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "agent_payment_hold:backfill_payment_due_at" do
  before(:all) do
    Rails.application.load_tasks
  end

  before { Rake::Task["agent_payment_hold:backfill_payment_due_at"].reenable }

  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 48) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, agent_payment_hold_hours: 5) }

  def invoke = Rake::Task["agent_payment_hold:backfill_payment_due_at"].invoke

  it "stamps a fresh deadline on a pre-existing confirmed, unpaid agent booking" do
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                               status: "confirmed", payment_status: "pending", payment_due_at: nil,
                               check_in: Date.current + 30)

    travel_to(Time.zone.parse("2026-10-01 09:00")) { invoke }

    expect(booking.reload.payment_due_at).to eq(Time.zone.parse("2026-10-01 09:00") + 5.hours)
  end

  it "leaves a direct-bill agency's booking alone" do
    relationship.update!(relationship_type: "direct_bill")
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                               status: "confirmed", payment_status: "pending", payment_due_at: nil)

    invoke

    expect(booking.reload.payment_due_at).to be_nil
  end

  it "does not touch a booking that already carries a deadline" do
    existing_due_at = 2.hours.from_now
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                               status: "confirmed", payment_status: "pending", payment_due_at: existing_due_at)

    invoke

    expect(booking.reload.payment_due_at).to be_within(1.second).of(existing_due_at)
  end

  it "does not touch a cancelled or paid booking" do
    cancelled = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                                 status: "cancelled", payment_status: "pending", payment_due_at: nil)
    paid = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                            status: "confirmed", payment_status: "captured", payment_due_at: nil)

    invoke

    expect(cancelled.reload.payment_due_at).to be_nil
    expect(paid.reload.payment_due_at).to be_nil
  end

  it "is safe to run twice" do
    booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                               status: "confirmed", payment_status: "pending", payment_due_at: nil)

    invoke
    first_due_at = booking.reload.payment_due_at

    Rake::Task["agent_payment_hold:backfill_payment_due_at"].reenable
    travel(1.hour) { invoke }

    expect(booking.reload.payment_due_at).to be_within(1.second).of(first_due_at)
  end
end
