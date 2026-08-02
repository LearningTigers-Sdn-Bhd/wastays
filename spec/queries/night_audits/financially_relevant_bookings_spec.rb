# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::FinanciallyRelevantBookings do
  let(:hotel) { create(:hotel, time_zone: "Asia/Kuala_Lumpur") }
  let(:business_date) { Date.new(2026, 5, 20) }

  it "returns stays intersecting the date and no-shows arriving on the date" do
    checked_in = create_booking(status: "checked_in", check_in: business_date, check_out: business_date + 1.day)
    no_show = create_booking(status: "no_show", check_in: business_date, check_out: business_date + 1.day)
    create_booking(status: "confirmed", check_in: business_date, check_out: business_date + 1.day)
    create_booking(status: "completed", check_in: business_date - 2.days, check_out: business_date - 1.day)
    create_booking(hotel: create(:hotel), status: "checked_in", check_in: business_date, check_out: business_date + 1.day)

    result = described_class.call(hotel:, business_date:)

    expect(result).to be_an(ActiveRecord::Relation)
    expect(result).to contain_exactly(checked_in, no_show)
  end

  it "eager loads the associations used by audit evaluation" do
    booking = create_booking(status: "checked_in", check_in: business_date, check_out: business_date + 1.day)
    create(:booking_folio, booking:)

    loaded_booking = described_class.call(hotel:, business_date:).load.first

    expect(loaded_booking.association(:payment_transactions)).to be_loaded
    expect(loaded_booking.association(:refund_request)).to be_loaded
    expect(loaded_booking.association(:booking_rooms)).to be_loaded
    expect(loaded_booking.association(:booking_folio)).to be_loaded
    expect(loaded_booking.booking_folio.association(:folio_transactions)).to be_loaded
  end

  def create_booking(hotel: self.hotel, status:, check_in:, check_out:)
    create(:booking, hotel:, status:, check_in:, check_out:)
  end
end
