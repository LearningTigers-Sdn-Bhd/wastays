# frozen_string_literal: true

require "rails_helper"

RSpec.describe Refunds::Eligibility do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "confirmed", source: "ota", check_in: 4.days.from_now) }
  let!(:policy) { create(:refund_policy, min_days_before_checkin: 2, refund_percentage: 100.0) }

  subject { described_class.new(booking) }

  it "returns success for an eligible online booking" do
    result = subject.call
    expect(result.success?).to be true
    expect(result.suggested_amount).to eq(booking.total_amount)
  end

  it "returns failure if no policy exists" do
    RefundPolicy.delete_all
    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to include("no policy defined")
  end

  it "returns failure for manual bookings" do
    booking.update(source: "walk_in")
    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to include("manual booking")
  end

  it "returns failure for manual at hotel guarantee" do
    booking.update(guarantee_method: "manual_at_hotel")
    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to include("manual booking")
  end

  it "returns failure if refund request already exists" do
    create(:refund_request, booking: booking)
    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to include("already exists")
  end

  it "returns failure if policy window is missed" do
    booking.update(check_in: 1.day.from_now)
    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("There will be no refund because the refund policy was not followed.")
  end

  it "uses updated_at for cancelled bookings to check window" do
    booking.update(status: "cancelled", check_in: 3.days.from_now)
    # If it was cancelled just now, 3 days out is fine for a 2-day policy
    expect(subject.call.success?).to be true

    # If it was "cancelled" in the past (manually setting updated_at for test)
    booking.update_columns(updated_at: 2.days.from_now)
    # check_in (3 days from now) - reference (2 days from now) = 1 day < 2 min_days
    expect(subject.call.success?).to be false
  end
end
