require "rails_helper"

RSpec.describe BookingMailer, type: :mailer do
  let(:hotel) { create(:hotel, name: "Seaview Hotel", city: "Kuala Lumpur", country: "Malaysia") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe King") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha Rahman",
      guest_email: "aisha@example.com",
      guest_phone: "+60123456789",
      confirmation_token: "MAIL2A",
      total_amount: 300.0,
      currency: "MYR",
      payment_status: "captured",
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0,
      check_in: Date.new(2026, 5, 1),
      check_out: Date.new(2026, 5, 3),
      status: "pending"
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      subtotal: 300.0,
      room_type_snapshot: { "name" => "Deluxe King" }
    )
  end
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, status: "closed", invoice_number: 123) }

  before do
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 300,
      description: "Room Charge - Deluxe King")
    create(:folio_invoice, booking_folio: folio)
  end

  subject(:mail) { described_class.invoice(booking) }

  it "sends to the guest email" do
    expect(mail.to).to eq([ "aisha@example.com" ])
  end

  it "includes the confirmation token in the subject" do
    expect(mail.subject).to include("MAIL2A")
  end

  it "attaches the invoice PDF with correct filename" do
    pdf_attachment = mail.attachments.find { |a| a.filename == "wastays-invoice-MAIL2A.pdf" }
    expect(pdf_attachment).not_to be_nil
    expect(pdf_attachment.content_type).to include("application/pdf")
  end

  it "has exactly one non-inline attachment" do
    non_inline = mail.attachments.reject(&:inline?)
    expect(non_inline.count).to eq(1)
  end

  it "does not generate an invoice for a booking without a closed folio" do
    booking_without_folio = create(:booking, hotel: hotel, guest_email: "no-folio@example.com")

    expect { described_class.invoice(booking_without_folio).message }
      .to raise_error(::Reports::Bookings::GenerateFolioRecords::UnavailableError)
  end
end
