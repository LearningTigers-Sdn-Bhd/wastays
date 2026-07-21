# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ApplyBillTo do
  let(:booking) { create(:booking) }
  let(:hotel) { booking.hotel }
  let(:actor) { create(:user, account: hotel.account) }
  let(:corporate_account) { create(:hotel_corporate_account, hotel: hotel) }

  before do
    Folios::InitializeForBooking.call(booking: booking, user: actor, lock: false)
  end

  it "ensures a company folio and routes room revenue to it, leaving the guest folio guest-owned" do
    result = described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: corporate_account.id)

    expect(result.success?).to be(true)
    expect(result.party).to be_present

    guest_folio = booking.booking_folio
    expect(guest_folio).to have_attributes(is_primary: true, payer_type: "guest", hotel_corporate_account_id: nil)

    expect(result.target_folio).to have_attributes(folio_type: "external", payer_type: "company",
      hotel_corporate_account_id: corporate_account.id)

    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    rule = booking.folio_routing_rules.active.find_by(transaction_code: room_code)
    expect(rule&.target_folio_id).to eq(result.target_folio.id)
  end

  it "leaves tourism tax on the guest folio by default" do
    described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: corporate_account.id)

    tourism_code = hotel.transaction_codes.find_by!(system_key: "tourism_tax")
    expect(booking.folio_routing_rules.active.find_by(transaction_code: tourism_code)).to be_nil
  end

  it "routes tourism tax to the company folio when requested" do
    result = described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: corporate_account.id,
      bill_tourism_tax_to_company: true)

    tourism_code = hotel.transaction_codes.find_by!(system_key: "tourism_tax")
    rule = booking.folio_routing_rules.active.find_by(transaction_code: tourism_code)
    expect(rule&.target_folio_id).to eq(result.target_folio.id)
  end

  it "fails when the corporate account is not valid for the hotel" do
    result = described_class.call(booking: booking, actor: actor, hotel_corporate_account_id: 0)

    expect(result.success?).to be(false)
    expect(result.error).to be_present
  end
end
