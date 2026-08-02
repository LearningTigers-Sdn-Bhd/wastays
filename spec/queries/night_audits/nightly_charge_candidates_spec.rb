# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::NightlyChargeCandidates do
  let(:hotel) { create(:hotel, time_zone: "Asia/Kuala_Lumpur") }
  let(:business_date) { Date.new(2026, 5, 20) }

  it "returns only checked-in bookings occupying the audited night" do
    candidate = create_booking(status: "checked_in", check_in: business_date, check_out: business_date + 1.day)
    create_booking(status: "checked_in", check_in: business_date - 1.day, check_out: business_date)
    create_booking(status: "completed", check_in: business_date, check_out: business_date + 1.day)
    create_booking(hotel: create(:hotel), status: "checked_in", check_in: business_date, check_out: business_date + 1.day)

    result = described_class.call(hotel:, business_date:)

    expect(result).to be_an(ActiveRecord::Relation)
    expect(result).to contain_exactly(candidate)
  end

  it "eager loads rooms, folios, and folio transactions" do
    booking = create_booking(status: "checked_in", check_in: business_date, check_out: business_date + 1.day)
    folio = create(:booking_folio, booking:)
    create(:folio_transaction, booking_folio: folio, posting_date: business_date)

    loaded_booking = described_class.call(hotel:, business_date:).load.first

    expect(loaded_booking.association(:booking_rooms)).to be_loaded
    expect(loaded_booking.association(:booking_folios)).to be_loaded
    expect(loaded_booking.booking_folios.first.association(:folio_transactions)).to be_loaded
  end

  def create_booking(hotel: self.hotel, status:, check_in:, check_out:)
    create(:booking, hotel:, status:, check_in:, check_out:)
  end
end
