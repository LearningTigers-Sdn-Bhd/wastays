# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposit do
  it "records held security deposits with transaction code labels" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking)

    deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, amount: 150)

    expect(deposit.hold_type).to eq("security")
    expect(deposit.status).to eq("held")
    expect(deposit.transaction_code).to have_attributes(system_key: "security_deposit", code: "SECDEP", gl_account_code: "2030")
    expect(deposit.collected_at).to be_present
  end

  it "requires the folio to belong to the same booking" do
    booking = create(:booking)
    other_folio = create(:booking_folio)

    deposit = build(:deposit, booking: booking, hotel: booking.hotel, booking_folio: other_folio)

    expect(deposit).not_to be_valid
    expect(deposit.errors[:booking_folio]).to include("must belong to the same booking")
  end

  it "requires the transaction code to be a security deposit code for the same hotel" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking)
    cash_code = booking.hotel.transaction_codes.find_by!(system_key: "cash_payment")

    deposit = build(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio, transaction_code: cash_code)

    expect(deposit).not_to be_valid
    expect(deposit.errors[:transaction_code]).to include("must be a security deposit code")
  end
end
