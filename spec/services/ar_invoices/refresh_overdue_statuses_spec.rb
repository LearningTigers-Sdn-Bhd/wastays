# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoices::RefreshOverdueStatuses do
  it "marks open outstanding past-due invoices overdue without touching paid or void invoices" do
    hotel = create(:hotel)
    relationship = create(:hotel_corporate_account, hotel: hotel)
    as_of_date = Date.new(2026, 6, 25)
    open_invoice = create_invoice(relationship: relationship, status: "open", amount: 100, outstanding_amount: 100, due_on: as_of_date - 1.day)
    partial_invoice = create_invoice(relationship: relationship, status: "partially_paid", amount: 100, outstanding_amount: 20, due_on: as_of_date - 1.day)
    paid_invoice = create_invoice(relationship: relationship, status: "paid", amount: 100, outstanding_amount: 0, due_on: as_of_date - 1.day)
    void_invoice = create_invoice(relationship: relationship, status: "void", amount: 100, outstanding_amount: 100, due_on: as_of_date - 1.day)
    current_invoice = create_invoice(relationship: relationship, status: "open", amount: 100, outstanding_amount: 100, due_on: as_of_date)

    expect(described_class.call(hotel: hotel, as_of_date: as_of_date)).to eq(2)

    expect(open_invoice.reload).to be_overdue
    expect(partial_invoice.reload).to be_overdue
    expect(paid_invoice.reload).to be_paid
    expect(void_invoice.reload).to be_void
    expect(current_invoice.reload).to be_open
  end

  def create_invoice(relationship:, status:, amount:, outstanding_amount:, due_on:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, status: status, amount: amount, outstanding_amount: outstanding_amount, issued_on: due_on - 30.days, due_on: due_on)
  end
end
