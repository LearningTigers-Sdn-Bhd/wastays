require "rails_helper"

RSpec.describe Concierge::StayAccess::VerifyDevice do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:stay_access) { create(:concierge_stay_access, hotel: hotel, booking: booking) }
  let(:code) { booking.confirmation_token }

  def verify(value = code, record: stay_access, now: Time.current)
    described_class.new(
      stay_access: record,
      confirmation_code: value,
      request_ip: "1.2.3.4",
      now: now
    ).call
  end

  # A wrong attempt sets a growing delay, so a spec that sends two codes in a
  # row must move the clock past it.
  def verify_later(value, seconds: 60)
    verify(value, now: Time.current + seconds)
  end

  it "accepts the confirmation code" do
    result = verify

    expect(result.success?).to be true
    expect(result.booking).to eq(booking)
  end

  it "accepts the code in lower case and with spaces" do
    expect(verify(" #{code.downcase} ").success?).to be true
  end

  it "refuses a wrong code" do
    result = verify("WS-WRONG")

    expect(result.success?).to be false
    expect(result.error).to eq(described_class::GENERIC_ERROR)
    expect(stay_access.reload.attempt_count).to eq(1)
  end

  it "refuses a blank code" do
    expect(verify("").success?).to be false
  end

  it "gives the same message for a wrong code and for an unavailable stay" do
    confirmed = create(:booking, hotel: hotel, status: "confirmed")
    # A booking can fall out of eligibility after its record exists, so the
    # record is built here and saved without the eligibility gate.
    other = build(:concierge_stay_access, hotel: hotel, booking: confirmed,
      stay_access_id: SecureRandom.alphanumeric(12))
    other.save!(validate: false)

    expect(verify("WS-WRONG").error).to eq(verify(code, record: other).error)
  end

  it "asks the guest to wait when a second code arrives too soon" do
    verify("WS-WRONG")
    result = verify("WS-WRONG")

    expect(result.success?).to be false
    expect(result.error).to eq(described_class::SLOW_DOWN_ERROR)
    expect(result.retry_after).to be_positive
  end

  it "grows the delay after each wrong code" do
    verify("WS-WRONG")
    first_gap = verify("WS-WRONG").retry_after

    verify_later("WS-WRONG", seconds: 30)
    second_gap = verify_later("WS-WRONG", seconds: 30).retry_after

    expect(second_gap).to be > first_gap
  end

  it "locks the record on the fifth wrong code" do
    5.times { |index| verify_later("WS-WRONG", seconds: index * 60) }

    stay_access.reload
    expect(stay_access.attempt_count).to eq(5)
    expect(stay_access.locked?).to be true
  end

  it "refuses the correct code while the record is locked" do
    locked = create(:concierge_stay_access, :locked, hotel: hotel, booking: booking)
    result = verify(code, record: locked)

    expect(result.success?).to be false
    expect(result.locked).to be true
    expect(result.error).to eq(described_class::LOCKED_ERROR)
  end

  it "accepts the code again after the lock runs out" do
    locked = create(:concierge_stay_access, :locked, hotel: hotel, booking: booking)

    expect(verify(code, record: locked, now: 2.hours.from_now).success?).to be true
  end

  it "starts the budget again after the attempt window closes" do
    verify("WS-WRONG")
    result = verify("WS-WRONG", now: 2.hours.from_now)

    expect(result.error).to eq(described_class::GENERIC_ERROR)
    expect(stay_access.reload.attempt_count).to eq(1)
  end

  it "clears the attempt count after a correct code" do
    verify("WS-WRONG")
    verify_later(code)

    stay_access.reload
    expect(stay_access.attempt_count).to eq(0)
    expect(stay_access.last_attempt_at).to be_nil
  end

  it "refuses a revoked record" do
    revoked = create(:concierge_stay_access, :revoked, hotel: hotel, booking: booking)

    expect(verify(code, record: revoked).success?).to be false
  end

  it "refuses a missing record" do
    expect(verify(code, record: nil).success?).to be false
  end

  it "keeps the raw code out of the log" do
    allow(Rails.logger).to receive(:info)
    verify("WS-SECRET")

    expect(Rails.logger).to have_received(:info) do |message|
      expect(message).not_to include("WS-SECRET")
      expect(message).to include("stay_access=#{stay_access.id}")
    end
  end
end
