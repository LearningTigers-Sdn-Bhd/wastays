# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::Prepare do
  let(:hotel) { create(:hotel, :without_current_business_date) }
  let(:business_date) { Date.current - 1.day }

  before { BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date) }

  it "previews readiness without creating an audit or locking the business date" do
    booking = create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 1.day, checked_in_at: Time.current)

    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result.ready).to be(false)
    expect(result.night_audit).to be_nil
    expect(result.evaluation[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
    expect(hotel.night_audits).to be_empty
    expect(hotel.current_business_date_record).to be_open
    expect(hotel.current_business_date_record.blockers_snapshot).to eq({})
  end

  it "returns an existing preparation without mutating it" do
    existing = create(:night_audit, hotel: hotel, business_date: business_date, status: "preparing")
    original_updated_at = existing.updated_at
    result = described_class.call(hotel: hotel, business_date: business_date)

    expect(result.night_audit.id).to eq(existing.id)
    expect(existing.reload.updated_at).to eq(original_updated_at)
  end
end
