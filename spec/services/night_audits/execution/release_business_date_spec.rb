require "rails_helper"

RSpec.describe NightAudits::Execution::ReleaseBusinessDate do
  let(:business_date) { Date.new(2026, 8, 1) }
  let(:hotel) { create(:hotel, :without_current_business_date) }

  it "reopens the current running business date and clears audit state" do
    record = create(:hotel_business_date,
      hotel: hotel,
      business_date: business_date,
      status: "audit_running",
      audit_started_at: Time.current,
      blocked_at: Time.current,
      blockers_snapshot: { "missing_folio" => [ { "booking_id" => 123 } ] })

    result = described_class.call!(hotel: hotel, business_date: business_date)

    expect(result).to eq(record)
    expect(record.reload).to have_attributes(
      status: "open",
      audit_started_at: nil,
      blocked_at: nil,
      blockers_snapshot: {}
    )
  end

  it "rejects a business date that is not running" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "open")

    expect do
      described_class.call!(hotel: hotel, business_date: business_date)
    end.to raise_error(
      HotelBusinessDate::InvalidTransition,
      "Night Audit can only release its current running business date."
    )
  end

  it "rejects a date other than the current running business date" do
    create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "audit_running")

    expect do
      described_class.call!(hotel: hotel, business_date: business_date + 1.day)
    end.to raise_error(
      HotelBusinessDate::InvalidTransition,
      "Night Audit can only release its current running business date."
    )
  end
end
