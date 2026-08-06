# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::AgingPresenter do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      credit_limit: 100,
      credit_currency: "MYR",
      corporate_account: create(:account, :corporate, name: "Atlas Holdings")
    )
  end
  let(:as_of_date) { Date.new(2026, 6, 25) }

  it "formats currency-separated metrics and comparable credit status" do
    create_invoice(amount: 90, currency: "MYR", due_on: as_of_date - 10.days)
    create_invoice(amount: 25, currency: "USD", due_on: as_of_date - 40.days)
    report = ArInvoices::AgingReport.call(hotel: hotel, as_of_date: as_of_date)
    presenter = described_class.new(report: report)

    metrics = presenter.summary_metrics.index_by(&:label)
    myr_row = presenter.rows.find { |row| row.currency == "MYR" }
    usd_row = presenter.rows.find { |row| row.currency == "USD" }

    expect(metrics.fetch("1–30 days").amounts).to eq([ "MYR 90.00", "USD 0.00" ])
    expect(metrics.fetch("31–60 days").amounts).to eq([ "MYR 0.00", "USD 25.00" ])
    expect(metrics.fetch("Total outstanding").amounts).to eq([ "MYR 90.00", "USD 25.00" ])
    expect(myr_row.credit_status_label).to eq("Near limit")
    expect(myr_row.credit_status_description).to include("90% of credit limit")
    expect(usd_row.credit_status_label).to eq("Not comparable")
    expect(usd_row.credit_status_description).to eq("Credit limit is configured in MYR")
    expect(myr_row.row.credit_exposure.warning_state).to eq("currency_mismatch")
    expect(myr_row.row.credit_exposure).to be_requires_override
  end

  def create_invoice(amount:, currency:, due_on:)
    booking = create(:booking, hotel: hotel, currency: currency)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      hotel_corporate_account: relationship,
      currency: currency
    )
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      outstanding_amount: amount,
      currency: currency,
      issued_on: due_on - 30.days,
      due_on: due_on
    )
  end
end
