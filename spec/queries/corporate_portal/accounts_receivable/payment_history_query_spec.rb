# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AccountsReceivable::PaymentHistoryQuery do
  let(:account) { create(:account, :corporate) }
  let(:relationship) { create(:hotel_corporate_account, corporate_account: account) }
  let(:corporate_user) { create(:user, account: account, role: "corporate") }

  it "returns an exact count and bounded, deterministic locators" do
    timestamp = Time.zone.local(2026, 9, 1, 12)
    payments = Array.new(30) do |index|
      create(
        :ar_payment,
        hotel_corporate_account: relationship,
        hotel: relationship.hotel,
        reference_number: "PAGE-#{index}",
        received_at: timestamp.to_date,
        created_at: timestamp
      )
    end

    result = query.call(page: 2, limit: 25)

    expect(result.count).to eq(30)
    expect(result.locators.size).to eq(30)
    expect(result.locators.map(&:source_id)).to eq(payments.sort_by(&:id).reverse.map(&:id))
  end

  it "filters each source before it creates page locators" do
    pending_intent = create(:corporate_ar_payment_intent, hotel_corporate_account: relationship, user: corporate_user, status: "pending")
    failed_intent = create(:corporate_ar_payment_intent, hotel_corporate_account: relationship, user: corporate_user, status: "failed")
    legacy_payment = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel)
    pending_submission = create(:ar_payment_submission, hotel_corporate_account: relationship, status: "pending")

    expect(locator_keys("pending")).to eq([ [ :intent, pending_intent.id ] ])
    expect(locator_keys("failed")).to eq([ [ :intent, failed_intent.id ] ])
    expect(locator_keys("pending_review")).to eq([ [ :submission, pending_submission.id ] ])
    expect(locator_keys("pending")).not_to include([ :payment, legacy_payment.id ])
  end

  it "uses the active allocation amount for all allocation-status filters" do
    invoice = create_invoice
    unapplied = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel, amount: 100)
    partial = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel, amount: 100)
    full = create(:ar_payment, hotel_corporate_account: relationship, hotel: relationship.hotel, amount: 100)
    create(:ar_payment_allocation, ar_payment: partial, ar_invoice: invoice, amount: 40)
    allocation = create(:ar_payment_allocation, ar_payment: full, ar_invoice: invoice, amount: 100)

    expect(locator_ids("unapplied")).to include(unapplied.id)
    expect(locator_ids("partially_allocated")).to include(partial.id)
    expect(locator_ids("fully_allocated")).to include(full.id)

    create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reversed_by: create(:user), reason: "Correction")
    expect(locator_ids("unapplied")).to include(full.id)
    expect(locator_ids("fully_allocated")).not_to include(full.id)
  end

  private

  def query(status: nil)
    described_class.new(
      account: account,
      query: "",
      status: status,
      hotel_id: nil,
      received_from: nil,
      received_to: nil
    )
  end

  def locator_ids(status)
    query(status: status).call(page: 1, limit: 25).locators.map(&:source_id)
  end

  def locator_keys(status)
    query(status: status).call(page: 1, limit: 25).locators.map { |locator| [ locator.source_type, locator.source_id ] }
  end

  def create_invoice
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: relationship.hotel,
      hotel_corporate_account: relationship
    )
    create(
      :ar_invoice,
      hotel: relationship.hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: 200,
      outstanding_amount: 200
    )
  end
end
