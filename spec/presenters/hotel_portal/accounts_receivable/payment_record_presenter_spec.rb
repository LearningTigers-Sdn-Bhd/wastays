# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::PaymentRecordPresenter do
  let(:hotel) { create(:hotel) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }

  it "shows a Received status for confirmed payments regardless of allocation state" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 500, currency: hotel.default_currency, received_at: hotel.current_business_date)
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: create_invoice(amount: 100), amount: 100)

    presenter = described_class.new(hotel: hotel, params: {})
    row = presenter.paginated_rows.first

    expect(row).to have_attributes(status_label: "Received")
  end

  it "totals bank transfer payments received in the current business month, excluding other methods" do
    create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 300, currency: hotel.default_currency, payment_method: "bank_transfer", received_at: hotel.current_business_date)
    create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 999, currency: hotel.default_currency, payment_method: "cash", received_at: hotel.current_business_date)
    create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 999, currency: hotel.default_currency, payment_method: "bank_transfer", received_at: hotel.current_business_date - 2.months)

    presenter = described_class.new(hotel: hotel, params: {})
    metrics = presenter.summary_metrics.index_by(&:label)

    expect(metrics.fetch("Bank Transfers This Month").amounts).to eq([ "#{hotel.default_currency} 300.00" ])
  end

  it "merges in pending and rejected submissions, excluding approved ones" do
    pending_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship)
    rejected_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, status: "rejected", rejection_reason: "mismatch", reviewed_by: create(:user), reviewed_at: Time.current)
    approved_payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 50)
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, status: "approved", ar_payment: approved_payment, reviewed_by: create(:user), reviewed_at: Time.current)

    presenter = described_class.new(hotel: hotel, params: {})
    kinds_by_reference = presenter.paginated_rows.index_by(&:reference).transform_values(&:kind)

    expect(kinds_by_reference).to include(
      pending_submission.reference_number => :submission,
      rejected_submission.reference_number => :submission,
      approved_payment.reference_number => :payment
    )
    expect(presenter.paginated_rows.count { |row| row.kind == :submission }).to eq(2)
  end

  it "filters to pending submissions only" do
    pending_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100)

    presenter = described_class.new(hotel: hotel, params: { status: "pending" })

    expect(presenter.paginated_rows.map(&:reference)).to contain_exactly(pending_submission.reference_number)
  end

  def create_invoice(amount:)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: hotel.default_currency)
  end
end
