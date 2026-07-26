# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Charges::PostEarlyCheckoutCharges do
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
  let(:folio) { Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: user) }

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

  describe "billing routing" do
    let!(:primary_folio) { folio }
    let!(:company_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 9001) }
    let(:room_code) { hotel.transaction_codes.find_by(system_key: "room_revenue") || create(:transaction_code, hotel: hotel, system_key: "room_revenue", code: "ROOM") }
    let!(:routing_rule) { create(:folio_routing_rule, booking: booking, hotel: hotel, transaction_code: room_code, target_folio: company_folio) }

    it "posts routed room charges to the company folio instead of the guest folio" do
      result = described_class.call(
        booking: booking,
        folio: primary_folio,
        user: user,
        departure_date: departure_date,
        original_check_out: original_check_out
      )

      expect(result).to be_success
      expect(company_folio.folio_transactions.where("description LIKE ?", "Early checkout charge%").sum(:amount)).to eq(300.0)
      expect(primary_folio.folio_transactions.where("description LIKE ?", "Early checkout charge%")).to be_empty
    end

    it "leaves unrouted tax charges on the guest folio" do
      described_class.call(
        booking: booking,
        folio: primary_folio,
        user: user,
        departure_date: departure_date,
        original_check_out: original_check_out
      )

      expect(primary_folio.folio_transactions.where(category: "tax").sum(:amount)).to eq(20.0)
      expect(company_folio.folio_transactions.where(category: "tax")).to be_empty
    end

    it "routes to any target folio, not only company folios" do
      guest_split_folio = create(:booking_folio, booking: booking, hotel: hotel, folio_number: 9002, name: "Split Folio", is_primary: false, folio_type: "guest", payer_type: "guest")
      routing_rule.update!(target_folio: guest_split_folio)

      described_class.call(booking: booking, folio: primary_folio, user: user, departure_date: departure_date, original_check_out: original_check_out)

      expect(guest_split_folio.folio_transactions.where("description LIKE ?", "Early checkout charge%").sum(:amount)).to eq(300.0)
      expect(primary_folio.folio_transactions.where("description LIKE ?", "Early checkout charge%")).to be_empty
    end

    it "tags preview lines with the routed target folio" do
      lines = described_class.new(
        booking: booking, folio: primary_folio, user: user,
        departure_date: departure_date, original_check_out: original_check_out
      ).preview

      room_lines = lines.select { |line| line[:category] == "early_departure_charge" }
      tax_lines = lines.select { |line| line[:category] == "tax" }

      expect(room_lines).to all(include(target_folio_id: company_folio.id))
      expect(tax_lines).to all(include(target_folio_id: primary_folio.id))
    end

    it "does not duplicate routed charges on retry" do
      2.times do
        described_class.call(
          booking: booking,
          folio: primary_folio,
          user: user,
          departure_date: departure_date,
          original_check_out: original_check_out
        )
      end

      expect(company_folio.folio_transactions.where("description LIKE ?", "Early checkout charge%").count).to eq(2)
    end
  end
end
