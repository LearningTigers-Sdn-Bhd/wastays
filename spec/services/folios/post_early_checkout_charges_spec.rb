# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostEarlyCheckoutCharges do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:departure_date) { hotel.current_business_date }
  let(:original_check_out) { departure_date + 2.days }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      check_in: departure_date,
      check_out: original_check_out,
      tax_lines: [ { "name" => "Service Tax", "amount" => "20.00", "type" => "service_tax" } ]
    )
  end
  let!(:booking_room) do
    create(
      :booking_room,
      booking: booking,
      room_type: room_type,
      subtotal: 300.0,
      nightly_rate_snapshot: {
        departure_date.iso8601 => { "price" => "120.00" },
        (departure_date + 1.day).iso8601 => { "price" => "180.00" }
      }
    )
  end
  let(:folio) { Folios::InitializeForBooking.call(booking: booking, user: user) }

  it "posts room and tax lines for each unused night" do
    result = described_class.call(
      booking: booking,
      folio: folio,
      user: user,
      departure_date: departure_date,
      original_check_out: original_check_out
    )

    expect(result).to be_success
    descriptions = folio.folio_transactions.order(:created_at).pluck(:description)
    expect(descriptions).to include(
      "Early checkout charge - Night 1",
      "Early checkout tax - Night 1 - Service Tax",
      "Early checkout charge - Night 2",
      "Early checkout tax - Night 2 - Service Tax"
    )
    expect(folio.folio_transactions.find_by(description: "Early checkout charge - Night 1").amount).to eq(120.0)
    expect(folio.folio_transactions.find_by(description: "Early checkout charge - Night 2").amount).to eq(180.0)
    expect(folio.folio_transactions.where(category: "tax").sum(:amount)).to eq(20.0)
  end

  it "does not duplicate lines on retry" do
    2.times do
      result = described_class.call(
        booking: booking,
        folio: folio,
        user: user,
        departure_date: departure_date,
        original_check_out: original_check_out
      )
      expect(result).to be_success
    end

    expect(folio.folio_transactions.where("metadata->>'posting_source' = ?", "early_departure").count).to eq(4)
  end

  it "falls back to averaged subtotal when nightly snapshots are missing" do
    booking_room.update!(nightly_rate_snapshot: {})

    result = described_class.call(
      booking: booking,
      folio: folio,
      user: user,
      departure_date: departure_date,
      original_check_out: original_check_out
    )

    expect(result).to be_success
    expect(folio.folio_transactions.find_by(description: "Early checkout charge - Night 1").amount).to eq(150.0)
    expect(folio.folio_transactions.find_by(description: "Early checkout charge - Night 2").amount).to eq(150.0)
  end

  describe ".projected_checkout_balance" do
    it "excludes overlapping forecasted charges to avoid double-counting with early departure charges" do
      create(:folio_transaction,
             booking_folio: folio,
             transaction_type: "payment",
             category: "booking_payment",
             amount: 320.0,
             posting_date: Date.current,
             user: user)

      projected = described_class.projected_checkout_balance(
        folio: folio.reload,
        departure_date: departure_date,
        original_check_out: original_check_out
      )

      expect(projected).to eq(0.0)
    end

    it "reflects partial payments accurately" do
      create(:folio_transaction,
             booking_folio: folio,
             transaction_type: "payment",
             category: "cash",
             amount: 100.0,
             posting_date: Date.current,
             user: user)

      projected = described_class.projected_checkout_balance(
        folio: folio.reload,
        departure_date: departure_date,
        original_check_out: original_check_out
      )

      expect(projected).to eq(220.0)
    end
  end
end
