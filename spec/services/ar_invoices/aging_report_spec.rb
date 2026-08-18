# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoices::AgingReport do
  it "ages positive balances by due date, account, and currency without mixing totals" do
    hotel = create(:hotel, default_currency: "MYR")
    primary = create(
      :hotel_corporate_account,
      hotel: hotel,
      credit_limit: 1_000,
      credit_currency: "MYR",
      corporate_account: create(:account, :corporate, name: "Atlas Holdings")
    )
    secondary = create(
      :hotel_corporate_account,
      hotel: hotel,
      credit_limit: 500,
      corporate_account: create(:account, :corporate, name: "Beacon Group")
    )
    other_hotel_relationship = create(:hotel_corporate_account)
    as_of_date = Date.new(2026, 6, 25)

    create_invoice(relationship: primary, amount: 50, due_on: as_of_date + 1.day)
    create_invoice(relationship: primary, amount: 100, due_on: as_of_date)
    create_invoice(relationship: primary, amount: 200, outstanding_amount: 125, status: "partially_paid", due_on: as_of_date - 1.day)
    create_invoice(relationship: primary, amount: 300, due_on: as_of_date - 30.days)
    create_invoice(relationship: primary, amount: 400, due_on: as_of_date - 31.days)
    create_invoice(relationship: primary, amount: 500, due_on: as_of_date - 60.days)
    create_invoice(relationship: primary, amount: 600, due_on: as_of_date - 61.days)
    create_invoice(relationship: primary, amount: 700, due_on: as_of_date - 90.days)
    create_invoice(relationship: primary, amount: 800, due_on: as_of_date - 91.days)
    create_invoice(relationship: primary, amount: 25, currency: "USD", due_on: as_of_date - 15.days)
    create_invoice(relationship: secondary, amount: 10, due_on: as_of_date - 15.days)
    create_invoice(relationship: primary, amount: 20, outstanding_amount: 0, status: "paid", due_on: as_of_date - 15.days)
    create_invoice(relationship: primary, amount: 20, outstanding_amount: 0, status: "void", due_on: as_of_date - 15.days)
    create_invoice(relationship: primary, amount: 20, outstanding_amount: 0, due_on: as_of_date - 15.days)
    create_invoice(relationship: other_hotel_relationship, amount: 999, due_on: as_of_date - 15.days)

    report = described_class.call(hotel: hotel, as_of_date: as_of_date)
    myr_row = report.rows.find { |row| row.hotel_corporate_account == primary && row.currency == "MYR" }
    usd_row = report.rows.find { |row| row.hotel_corporate_account == primary && row.currency == "USD" }

    expect(report.rows.size).to eq(3)
    expect(myr_row.buckets).to have_attributes(
      current: 150.to_d,
      days_1_30: 425.to_d,
      days_31_60: 900.to_d,
      days_61_90: 1_300.to_d,
      days_over_90: 800.to_d
    )
    expect(myr_row.total_outstanding).to eq(3_575.to_d)
    expect(usd_row.total_outstanding).to eq(25.to_d)
    expect(usd_row.credit_comparable?).to be(false)
    expect(report.totals.fetch("MYR").days_1_30).to eq(435.to_d)
    expect(report.totals.fetch("USD").days_1_30).to eq(25.to_d)
    expect(report.rows.map { |row| [ row.corporate_account.name, row.currency ] }).to eq(
      [ [ "Atlas Holdings", "MYR" ], [ "Atlas Holdings", "USD" ], [ "Beacon Group", "MYR" ] ]
    )
  end

  it "filters rows by account_types when provided" do
    hotel = create(:hotel, default_currency: "MYR")
    agent = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent",
      corporate_account: create(:account, :corporate, name: "Sunset Travel Agency"))
    company = create(:hotel_corporate_account, hotel: hotel, account_type: "company",
      corporate_account: create(:account, :corporate, name: "Acme Sdn Bhd"))
    as_of_date = Date.new(2026, 6, 25)

    create_invoice(relationship: agent, amount: 100, due_on: as_of_date - 15.days)
    create_invoice(relationship: company, amount: 200, due_on: as_of_date - 15.days)

    report = described_class.call(hotel: hotel, as_of_date: as_of_date, account_types: %w[travel_agent airline])

    expect(report.rows.map { |row| row.corporate_account.name }).to eq([ "Sunset Travel Agency" ])
    expect(report.totals.fetch("MYR").total).to eq(100.to_d)
  end

  it "filters rows and totals by corporate account name when a query is provided" do
    hotel = create(:hotel, default_currency: "MYR")
    matching = create(:hotel_corporate_account, hotel: hotel,
      corporate_account: create(:account, :corporate, name: "Megat Holdings"))
    hidden = create(:hotel_corporate_account, hotel: hotel,
      corporate_account: create(:account, :corporate, name: "Acme Sdn Bhd"))
    as_of_date = Date.new(2026, 6, 25)

    create_invoice(relationship: matching, amount: 100, due_on: as_of_date - 15.days)
    create_invoice(relationship: hidden, amount: 200, due_on: as_of_date - 15.days)

    report = described_class.call(hotel: hotel, as_of_date: as_of_date, query: "  megat  ")

    expect(report.rows.map { |row| row.corporate_account.name }).to eq([ "Megat Holdings" ])
    expect(report.totals.fetch("MYR").total).to eq(100.to_d)
  end

  def create_invoice(
    relationship:,
    amount:,
    due_on:,
    outstanding_amount: amount,
    status: "open",
    currency: "MYR"
  )
    booking = create(:booking, hotel: relationship.hotel, currency: currency)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: relationship.hotel,
      hotel_corporate_account: relationship,
      currency: currency
    )
    create(
      :ar_invoice,
      hotel: relationship.hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      paid_amount: amount.to_d - outstanding_amount.to_d,
      outstanding_amount: outstanding_amount,
      status: status,
      currency: currency,
      issued_on: due_on - 30.days,
      due_on: due_on
    )
  end
end
