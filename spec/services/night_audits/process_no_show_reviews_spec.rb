# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ProcessNoShowReviews do
  let(:business_date) { Date.new(2026, 5, 18) }
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }
  let(:user) { create(:user, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 5, room_numbers: [ "101" ]) }

  def audit(date)
    current = hotel.current_business_date_record
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: date) unless current.business_date <= date

    while hotel.reload.current_business_date < date
      close_and_open_next_business_date(hotel)
    end

    start_business_date_audit(hotel) if hotel.current_business_date_record.open?
    create(:night_audit, hotel: hotel, business_date: date, performed_by_user: user, status: "running", started_at: Time.current)
  end

  def candidate
    booking = create(
      :booking,
      hotel: hotel,
      status: "confirmed",
      check_in: business_date,
      check_out: business_date + 3.days,
      tax_lines: []
    )
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 300.0, quantity: 1, room_number: "101")
    booking
  end

  it "moves a missed arrival into review without charges or inventory release" do
    booking = candidate
    create(:room_inventory, room_type: room_type, date: business_date + 1.day, quantity: 0)

    result = described_class.call(night_audit: audit(business_date), user: user)

    expect(result.reviewed_count).to eq(1)
    expect(result.finalized_count).to eq(0)
    expect(booking.reload).to have_attributes(status: "review_no_show", no_show_review_business_date: business_date)
    expect(booking.booking_folio).to be_nil
    expect(room_type.room_inventories.find_by!(date: business_date + 1.day).quantity).to eq(0)
  end

  it "does not finalize a review during a retry for the same business date" do
    booking = candidate
    described_class.call(night_audit: audit(business_date), user: user)

    retry_audit = hotel.night_audits.find_by!(business_date: business_date)
    result = described_class.call(night_audit: retry_audit, user: user)

    expect(result.finalized_count).to eq(0)
    expect(booking.reload.status).to eq("review_no_show")
  end

  it "finalizes an unresolved review on the next business-date audit attempt" do
    booking = candidate
    create(:room_inventory, room_type: room_type, date: business_date + 1.day, quantity: 0)
    described_class.call(night_audit: audit(business_date), user: user)

    result = described_class.call(night_audit: audit(business_date + 1.day), user: user)

    expect(result.finalized_count).to eq(1)
    expect(booking.reload.status).to eq("no_show")
    expect(booking.booking_folio.folio_transactions.charge.where(category: "no_show_charge").sole.amount).to eq(100.0)
    expect(room_type.room_inventories.find_by!(date: business_date + 1.day).quantity).to eq(1)
  end
end
