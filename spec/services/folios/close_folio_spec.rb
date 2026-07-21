# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CloseFolio do
  let(:booking) { create(:booking, status: "checked_in", currency: "MYR") }
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel, status: "open") }

  it "closes a zero-balance folio and records the operation" do
    expect {
      @result = described_class.call(folio: folio, user: user, reason: "Settled")
    }.to change(FolioOperationLog.where(operation_type: "close_folio"), :count).by(1)

    expect(@result).to be_success
    expect(folio.reload).to be_closed
    expect(folio.closed_at).to be_present
    expect(folio.closed_by).to eq(user)
    expect(FolioOperationLog.last).to have_attributes(source_folio: folio, reason: "Settled")
  end

  it "requires permission to manage folio windows" do
    result = described_class.call(folio: folio, user: create(:user))

    expect(result).not_to be_success
    expect(result.error).to include("permission")
    expect(folio.reload).to be_open
  end

  it "rejects a folio that is already closed" do
    folio.update!(status: "closed")

    expect(described_class.call(folio: folio, user: user).error).to eq("Folio is already closed.")
  end

  it "rejects a folio with pending forecasts" do
    create(:folio_forecasted_charge, booking_folio: folio)

    expect(described_class.call(folio: folio, user: user).error).to eq("Cannot close a folio with pending upcoming charges.")
    expect(folio.reload).to be_open
  end

  it "rejects a folio with a non-zero balance" do
    create(:folio_transaction, booking_folio: folio, amount: 125)

    expect(described_class.call(folio: folio, user: user).error).to eq("Cannot close folio with non-zero balance of MYR 125.00.")
    expect(folio.reload).to be_open
  end

  it "keeps guest folio positive-balance close rule unchanged when Direct Bill is requested" do
    create(:folio_transaction, booking_folio: folio, amount: 125)

    result = described_class.call(folio: folio, user: user, settlement_method: "direct_bill")

    expect(result).not_to be_success
    expect(result.error).to eq("Direct Bill settlement is only available for Company & Government folios.")
    expect(folio.reload).to be_open
  end

  it "rejects Direct Bill close when the company account is suspended" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel, status: "active")
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, hotel_corporate_account: relationship)
    relationship.suspend!
    create(:folio_transaction, booking_folio: company_folio, amount: 125)

    result = described_class.call(folio: company_folio, user: user, settlement_method: "direct_bill")

    expect(result).not_to be_success
    expect(result.error).to eq("Company & Government Account must be active for Direct Bill settlement.")
    expect(company_folio.reload).to be_open
  end

  it "rejects Direct Bill close when Direct Bill is disabled" do
    relationship = create(:hotel_corporate_account, hotel: booking.hotel, direct_bill_enabled: false)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, hotel_corporate_account: relationship)
    create(:folio_transaction, booking_folio: company_folio, amount: 125)

    result = described_class.call(folio: company_folio, user: user, settlement_method: "direct_bill")

    expect(result).not_to be_success
    expect(result.error).to eq("Direct Bill is not enabled for this Company & Government Account.")
    expect(company_folio.reload).to be_open
  end

  it "closes an eligible company folio as Direct Bill and creates an AR invoice" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel, payment_terms_days: 30)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, hotel_corporate_account: relationship)
    create(:folio_transaction, booking_folio: company_folio, amount: 125)

    expect {
      @result = described_class.call(folio: company_folio, user: user, reason: "Corporate credit", settlement_method: "direct_bill")
    }.to change(ArInvoice, :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "direct_bill_folio_closed"), :count).by(1)
      .and change(FolioOperationLog.where(operation_type: "close_folio"), :count).by(1)

    expect(@result).to be_success
    expect(company_folio.reload).to be_closed

    invoice = company_folio.ar_invoice
    expect(invoice).to have_attributes(
      hotel: booking.hotel,
      hotel_corporate_account: relationship,
      amount: 125.to_d,
      paid_amount: 0.to_d,
      outstanding_amount: 125.to_d,
      status: "open",
      currency: "MYR",
      issued_on: booking.hotel.current_business_date,
      due_on: booking.hotel.current_business_date + 30.days
    )
    expect(invoice.metadata).to include(
      "booking_id" => booking.id,
      "corporate_account_id" => relationship.corporate_account_id,
      "payment_terms_days" => 30,
      "folio_balance" => "125.0"
    )
    expect(FolioOperationLog.last.metadata).to include("settlement_method" => "direct_bill", "ar_invoice_id" => invoice.id)
  end

  it "prevents duplicate AR invoices for the same folio" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, hotel_corporate_account: relationship)
    create(:folio_transaction, booking_folio: company_folio, amount: 125)
    create(:ar_invoice, booking_folio: company_folio, hotel: booking.hotel, hotel_corporate_account: relationship)

    result = described_class.call(folio: company_folio, user: user, settlement_method: "direct_bill")

    expect(result).not_to be_success
    expect(result.error).to eq("AR invoice already exists for this folio.")
    expect(company_folio.reload).to be_open
  end

  it "blocks Direct Bill above the corporate credit limit unless explicitly overridden" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel, credit_limit: 100)
    company_folio = create(:booking_folio, :secondary, booking: booking, hotel: booking.hotel, hotel_corporate_account: relationship)
    create(:folio_transaction, booking_folio: company_folio, amount: 125)

    blocked = described_class.call(folio: company_folio, user: user, settlement_method: "direct_bill")
    overridden = described_class.call(
      folio: company_folio,
      user: user,
      settlement_method: "direct_bill",
      credit_override: true,
      credit_override_reason: "Approved by finance"
    )

    expect(blocked).not_to be_success
    expect(blocked.error).to include("credit limit exceeded")
    expect(overridden).to be_success
    expect(FolioOperationLog.last.metadata).to include(
      "corporate_credit_override" => true,
      "corporate_credit_override_reason" => "Approved by finance"
    )
  end
end
