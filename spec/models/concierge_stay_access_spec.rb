require "rails_helper"

RSpec.describe ConciergeStayAccess do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }

  it "assigns a random stay_access_id on create" do
    record = create(:concierge_stay_access, hotel: hotel, booking: booking)

    expect(record.stay_access_id).to match(/\A[A-Za-z0-9]{12}\z/)
  end

  it "gives two records two different ids" do
    other = create(:booking, hotel: hotel, status: "checked_in")
    first = create(:concierge_stay_access, hotel: hotel, booking: booking)
    second = create(:concierge_stay_access, hotel: hotel, booking: other)

    expect(first.stay_access_id).not_to eq(second.stay_access_id)
  end

  it "permits one live record for one booking" do
    create(:concierge_stay_access, hotel: hotel, booking: booking)
    second = build(:concierge_stay_access, hotel: hotel, booking: booking)

    expect(second).not_to be_valid
    expect(second.errors[:booking_id]).to be_present
  end

  it "permits a new live record after the first one is revoked" do
    first = create(:concierge_stay_access, hotel: hotel, booking: booking)
    first.update!(revoked_at: Time.current)

    expect(build(:concierge_stay_access, hotel: hotel, booking: booking)).to be_valid
  end

  it "reports a lock while locked_until is in the future" do
    record = create(:concierge_stay_access, :locked, hotel: hotel, booking: booking)

    expect(record.locked?).to be true
    expect(record.locked?(now: 2.hours.from_now)).to be false
  end

  it "gives the full budget when no attempt window is open" do
    record = create(:concierge_stay_access, hotel: hotel, booking: booking)

    expect(record.attempts_left).to eq(described_class::MAX_ATTEMPTS)
  end

  it "counts down the budget inside an open window" do
    record = create(:concierge_stay_access, hotel: hotel, booking: booking,
      attempt_count: 2, attempt_window_started_at: Time.current)

    expect(record.attempts_left).to eq(described_class::MAX_ATTEMPTS - 2)
  end

  it "ignores an attempt window that is more than one hour old" do
    record = create(:concierge_stay_access, hotel: hotel, booking: booking,
      attempt_count: 4, attempt_window_started_at: 2.hours.ago)

    expect(record.attempt_window_open?).to be false
    expect(record.attempts_left).to eq(described_class::MAX_ATTEMPTS)
  end

  it "belongs to one hotel through HotelScopable" do
    expect(described_class.ancestors).to include(HotelScopable)
  end
end
