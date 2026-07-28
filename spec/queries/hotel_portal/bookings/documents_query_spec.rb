# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Bookings::DocumentsQuery do
  include Rails.application.routes.url_helpers

  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:group) { create(:group_booking, hotel:) }
  let(:booking) { create(:booking, hotel:, group_booking: group, group_position: 1, guest_name: "Aina Rahman") }
  let(:sibling) { create(:booking, hotel:, group_booking: group, group_position: 2, guest_name: "Ben Tan") }

  before do
    UserHotelAccess.create!(user:, hotel:, role:)
    create(:booking_room, booking:, room_number: "101")
    create(:booking_room, booking: sibling, room_number: "202")
  end

  it "builds one hotel-scoped catalog across every child booking" do
    invoice_folio = create(:booking_folio, :secondary, booking:, hotel:, status: "closed", closed_at: Time.current)
    create(:folio_transaction, booking_folio: invoice_folio, transaction_type: "charge", amount: 240)
    create(:folio_transaction, booking_folio: invoice_folio, transaction_type: "payment", category: "cash", amount: 240)
    invoice = create(:folio_invoice, booking_folio: invoice_folio)

    direct_bill_account = create(:hotel_corporate_account, :direct_bill, hotel:)
    direct_bill_folio = create(
      :booking_folio,
      :secondary,
      booking: sibling,
      hotel:,
      status: "closed",
      hotel_corporate_account: direct_bill_account,
      payer_type: "company"
    )
    ar_invoice = create(:ar_invoice, booking_folio: direct_bill_folio, hotel:, hotel_corporate_account: direct_bill_account)
    deposit = create(:deposit, booking: sibling, hotel:, amount: 75)

    rows = described_class.call(booking:, group_booking: group, hotel:, user:)

    expect(rows.map(&:booking)).to include(booking.formatted_reservation_number, sibling.formatted_reservation_number)
    expect(rows.find { |row| row.key == "folio-invoice-revision-#{invoice.current_revision.id}" }).to have_attributes(
      type: "Folio invoice",
      context_type: "External",
      number: invoice.invoice_reference,
      amount: 240.to_d,
      href: hotel_folio_invoice_path(hotel, invoice_folio)
    )
    expect(rows.find { |row| row.key == "folio-ledger-#{invoice_folio.id}" }).to have_attributes(amount: 0.to_d, context_type: "External")
    expect(rows.find { |row| row.key == "folio-invoice-unavailable-#{direct_bill_folio.id}" }).to have_attributes(
      unavailable_reason: "Direct Bill uses AR invoice"
    )
    expect(rows.find { |row| row.key == "ar-invoice-#{ar_invoice.id}" }).to have_attributes(
      number: "Restricted",
      payer: "Restricted",
      unavailable_reason: "Permission required"
    )
    expect(rows).to include(have_attributes(
      type: "Deposit receipt",
      number: deposit.receipt.public_number,
      href: receipt_path(deposit.receipt.access_token)
    ))
    expect(rows).to include(have_attributes(type: "Payer statement", number: "Restricted"))
  end

  it "reveals AR documents and historical revisions only with their document permissions" do
    view_reports = Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" }
    view_audit_logs = Permission.find_or_create_by!(slug: "view_audit_logs") { |permission| permission.name = "View Audit Logs" }
    role.permissions << [ view_reports, view_audit_logs ]

    folio = create(:booking_folio, :secondary, booking:, hotel:, status: "closed", closed_at: Time.current)
    invoice = create(:folio_invoice, booking_folio: folio)
    revision = create(
      :folio_invoice_revision,
      folio_invoice: invoice,
      hotel:,
      revision_number: 2,
      document_reference: "#{invoice.invoice_reference}-2"
    )
    invoice.update!(current_revision_number: 2)

    direct_bill_account = create(:hotel_corporate_account, :direct_bill, hotel:)
    direct_bill_folio = create(:booking_folio, :secondary, booking: sibling, hotel:, status: "closed",
      hotel_corporate_account: direct_bill_account, payer_type: "company")
    ar_invoice = create(:ar_invoice, booking_folio: direct_bill_folio, hotel:, hotel_corporate_account: direct_bill_account)
    ar_invoice.update!(paid_amount: ar_invoice.amount, outstanding_amount: 0, status: "paid")

    rows = described_class.call(booking:, group_booking: group, hotel:, user:)

    historical = rows.find { |row| row.type == "Invoice revision" }
    expect(historical).to have_attributes(
      number: invoice.invoice_reference,
      href: hotel_folio_invoice_revision_path(hotel, folio, 1),
      historical: true
    )
    expect(rows.find { |row| row.key == "folio-invoice-revision-#{revision.id}" }).to have_attributes(
      number: "#{invoice.invoice_reference}-2",
      href: hotel_folio_invoice_path(hotel, folio)
    )
    expect(rows.find { |row| row.key == "ar-invoice-#{ar_invoice.id}" }).to have_attributes(
      number: ar_invoice.formatted_invoice_number,
      payer: direct_bill_account.corporate_account.name,
      amount: ar_invoice.amount,
      href: pdf_hotel_ar_invoice_path(hotel, ar_invoice)
    )
    expect(rows).to include(have_attributes(
      type: "Payer statement",
      href: hotel_ar_statement_path(hotel, direct_bill_account, format: :pdf, currency: ar_invoice.currency, report_type: "detail")
    ))
  end

  it "keeps a deposit receipt separate from an unavailable folio payment receipt" do
    deposit = create(:deposit, booking:, hotel:)

    rows = described_class.call(booking:, group_booking: group, hotel:, user:)

    expect(rows).to include(have_attributes(type: "Deposit receipt", number: deposit.receipt.public_number))
    expect(rows).to include(have_attributes(
      key: "payment-receipt-unavailable-booking-#{booking.id}",
      unavailable_reason: "No receipt has been issued"
    ))
  end

  it "attributes a split AR payment receipt to all affected bookings" do
    view_reports = Permission.find_or_create_by!(slug: "view_reports") { |permission| permission.name = "View Reports" }
    role.permissions << view_reports
    account = create(:hotel_corporate_account, :direct_bill, hotel:)
    first_folio = create(:booking_folio, :secondary, booking:, hotel:, status: "closed",
      hotel_corporate_account: account, payer_type: "company")
    second_folio = create(:booking_folio, :secondary, booking: sibling, hotel:, status: "closed",
      hotel_corporate_account: account, payer_type: "company")
    first_invoice = create(:ar_invoice, booking_folio: first_folio, hotel:, hotel_corporate_account: account, amount: 50)
    second_invoice = create(:ar_invoice, booking_folio: second_folio, hotel:, hotel_corporate_account: account, amount: 50)
    payment = create(:ar_payment, hotel:, hotel_corporate_account: account, amount: 100, currency: first_invoice.currency)
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: first_invoice, amount: 50)
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: second_invoice, amount: 50)

    rows = described_class.call(booking:, group_booking: group, hotel:, user:)

    expect(rows).to include(have_attributes(
      key: "ar-payment-receipt-multiple-#{payment.receipt.id}",
      booking: group.formatted_reservation_number,
      room: "Multiple rooms",
      amount: 100.to_d,
      href: receipt_path(payment.receipt.access_token)
    ))
  end

  it "rejects a booking or group from another hotel" do
    other_hotel = create(:hotel, status: "approved")
    other_group = create(:group_booking, hotel: other_hotel)
    other_booking = create(:booking, hotel: other_hotel)

    expect do
      described_class.call(booking:, group_booking: other_group, hotel:, user:)
    end.to raise_error(ActiveRecord::RecordNotFound)

    expect do
      described_class.call(booking: other_booking, group_booking: nil, hotel:, user:)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
