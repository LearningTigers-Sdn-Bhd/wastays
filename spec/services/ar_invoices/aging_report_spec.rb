# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoices::AgingReport do
  it "groups outstanding invoices by corporate account and bucket" do
    hotel = create(:hotel)
    relationship = create(:hotel_corporate_account, hotel: hotel, credit_limit: 1000)
    other_relationship = create(:hotel_corporate_account, hotel: hotel, credit_limit: 500)
    other_hotel_relationship = create(:hotel_corporate_account)
    as_of_date = Date.new(2026, 6, 25)

    create_invoice(relationship: relationship, amount: 100, due_on: as_of_date)
    create_invoice(relationship: relationship, amount: 200, due_on: as_of_date - 1.day)
    create_invoice(relationship: relationship, amount: 300, due_on: as_of_date - 31.days)
    create_invoice(relationship: relationship, amount: 400, due_on: as_of_date - 61.days)
    create_invoice(relationship: relationship, amount: 500, due_on: as_of_date - 91.days)
    create_invoice(relationship: other_relationship, amount: 25, due_on: as_of_date - 15.days)
    create_invoice(relationship: other_hotel_relationship, amount: 999, due_on: as_of_date - 15.days)

    report = described_class.call(hotel: hotel, as_of_date: as_of_date)
    row = report.rows.detect { |candidate| candidate.hotel_corporate_account == relationship }

    expect(report.rows.size).to eq(2)
    expect(row.buckets.current).to eq(100.to_d)
    expect(row.buckets.days_1_30).to eq(200.to_d)
    expect(row.buckets.days_31_60).to eq(300.to_d)
    expect(row.buckets.days_61_90).to eq(400.to_d)
    expect(row.buckets.days_over_90).to eq(500.to_d)
    expect(row.total_outstanding).to eq(1500.to_d)
    expect(report.totals.days_1_30).to eq(225.to_d)
  end

  def create_invoice(relationship:, amount:, due_on:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, outstanding_amount: amount, issued_on: due_on - 30.days, due_on: due_on)
  end
end
