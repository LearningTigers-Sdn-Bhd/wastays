# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioInvoicePackages::QueueDeliveries, type: :job do
  let(:hotel) { create(:hotel, hotel_prefix: "DLV") }
  let(:group) { create(:group_booking, hotel:) }

  it "combines same-payer invoices into one logged delivery" do
    first_booking = booking_for("payer@example.test", 1)
    second_booking = booking_for("payer@example.test", 2)
    first = finalized_invoice(first_booking)
    second = finalized_invoice(second_booking)

    expect do
      @result = described_class.call(
        hotel:,
        bookings: [ first_booking, second_booking ],
        anchor_booking: first_booking,
        source: "automatic_checkout"
      )
    end.to have_enqueued_job(Notifications::DeliverJob).once

    delivery = @result.deliveries.sole
    expect(delivery).to have_attributes(notification_type: "invoice_package", status: "pending")
    expect(delivery.payload["folio_invoice_ids"]).to contain_exactly(first.id, second.id)
    expect(delivery.payload["folio_invoice_revision_ids"]).to contain_exactly(first.current_revision.id, second.current_revision.id)
    expect(delivery.payload["recipient_email"]).to eq("payer@example.test")
  end

  it "separates different payers and logs a missing contact as skipped" do
    valid_booking = booking_for("valid@example.test", 1)
    missing_booking = booking_for("guest@example.test", 2)
    finalized_invoice(valid_booking)
    finalized_company_invoice(missing_booking)

    result = described_class.call(
      hotel:,
      bookings: [ valid_booking, missing_booking ],
      anchor_booking: valid_booking,
      source: "manual_resend"
    )

    expect(result.groups.size).to eq(2)
    expect(result.deliveries.map(&:status)).to contain_exactly("pending", "skipped")
    skipped = result.deliveries.find { |delivery| delivery.status == "skipped" }
    expect(skipped.error_message).to include("No saved email")
  end

  it "is idempotent for the same automatic invoice revisions" do
    booking = booking_for("payer@example.test", 1)
    finalized_invoice(booking)
    arguments = { hotel:, bookings: [ booking ], anchor_booking: booking, source: "automatic_checkout" }

    expect do
      2.times { described_class.call(**arguments) }
    end.to change(NotificationDelivery, :count).by(1)
  end

  def booking_for(email, position)
    create(:booking,
      hotel:,
      group_booking: group,
      group_position: position,
      guest_email: email,
      confirmation_token: "DLV-#{position}")
  end

  def finalized_invoice(booking)
    folio = create(:booking_folio, booking:, hotel:, status: "closed")
    FolioInvoices::Finalize.call!(folio:, issued_by: nil, balance: 0)
  end

  def finalized_company_invoice(booking)
    relationship = create(:hotel_corporate_account, hotel:, contact_email: nil)
    folio = create(:booking_folio,
      booking:,
      hotel:,
      status: "closed",
      is_primary: false,
      folio_type: "external",
      payer_type: "company",
      hotel_corporate_account: relationship)
    FolioInvoices::Finalize.call!(folio:, issued_by: nil, balance: 0)
  end
end
