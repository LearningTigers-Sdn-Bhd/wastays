# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::CreateIntent do
  let(:user) { create(:user, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: user.account) }

  it "creates an intent with oldest due first remittance suggestions" do
    later = create_invoice(amount: 200, due_on: Date.current + 10.days)
    earlier = create_invoice(amount: 100, due_on: Date.current + 1.day)

    result = described_class.call(
      user: user,
      hotel_corporate_account_id: relationship.id,
      invoice_ids: [ later.id, earlier.id ],
      amount: "250.00",
      currency: relationship.hotel.default_currency,
      gateway: "razorpay"
    )

    expect(result).to be_success
    expect(result.intent.remittance_suggestions.map { |row| row["invoice_number"] || row[:invoice_number] }).to eq([ earlier.invoice_number, later.invoice_number ])
    expect(result.intent.remittance_suggestions.map { |row| row["suggested_amount"] || row[:suggested_amount] }).to eq([ "100.0", "150.0" ])
  end

  it "rejects suspended relationships" do
    invoice = create_invoice(amount: 100)
    relationship.update!(status: "suspended", suspended_at: Time.current)

    result = described_class.call(
      user: user,
      hotel_corporate_account_id: relationship.id,
      invoice_ids: [ invoice.id ],
      amount: "100.00",
      currency: relationship.hotel.default_currency,
      gateway: "razorpay"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Corporate relationship is not available for payment.")
  end

  context "lump sum payments" do
    it "creates an intent without requiring invoice_ids, sourced from all open invoices" do
      later = create_invoice(amount: 200, due_on: Date.current + 10.days)
      earlier = create_invoice(amount: 100, due_on: Date.current + 1.day)

      result = described_class.call(
        user: user,
        hotel_corporate_account_id: relationship.id,
        invoice_ids: [],
        amount: "150.00",
        currency: relationship.hotel.default_currency,
        gateway: "razorpay",
        lump_sum: true
      )

      expect(result).to be_success
      expect(result.intent.metadata["lump_sum"]).to eq(true)
      expect(result.intent.metadata["selected_invoice_ids"]).to eq([])
      expect(result.intent.remittance_suggestions.map { |row| row["invoice_number"] }).to eq([ earlier.invoice_number, later.invoice_number ])
      expect(result.intent.remittance_suggestions.map { |row| row["suggested_amount"] }).to eq([ "100.0", "50.0" ])
    end

    it "still rejects a zero amount or suspended relationship" do
      relationship.update!(status: "suspended", suspended_at: Time.current)

      result = described_class.call(
        user: user,
        hotel_corporate_account_id: relationship.id,
        invoice_ids: [],
        amount: "100.00",
        currency: relationship.hotel.default_currency,
        gateway: "razorpay",
        lump_sum: true
      )

      expect(result).not_to be_success
      expect(result.error).to eq("Corporate relationship is not available for payment.")
    end
  end

  def create_invoice(amount:, due_on: Date.current + 30.days)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: relationship.hotel.default_currency, due_on: due_on)
  end
end
