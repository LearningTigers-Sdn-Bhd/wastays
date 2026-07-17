require "rails_helper"

RSpec.describe VoucherPdfService do
  let(:hotel) { create(:hotel, name: "Seaview Hotel") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha",
      confirmation_token: "WS-VOUCHER1",
      total_amount: 300.0,
      check_in: Date.new(2026, 5, 1),
      check_out: Date.new(2026, 5, 3),
      hotel_snapshot: { "property_policy" => { "check_in_time" => "3:00 PM", "cancellation_policy" => "No refund" } })
  end

  before do
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 300.0, room_type_snapshot: { "name" => "Deluxe" })
  end

  def pdf_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end

  it "generates a valid PDF binary" do
    pdf = described_class.new(booking).generate

    expect(pdf).to be_a(String)
    expect(pdf.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
    expect(pdf.bytesize).to be > 1500
  end

  it "renders reservation metadata, rate breakdown, and guest country" do
    booking.update!(
      created_at: Time.zone.local(2026, 7, 17, 12, 0),
      guest_country: "Singapore",
      tax_lines: [ { "name" => "SST", "amount" => 24.0 } ]
    )

    text = pdf_text(described_class.new(booking).generate)

    expect(text).to include(
      "RESERVATION NUMBER",
      booking.formatted_reservation_number,
      "BOOKING DATE",
      "17 Jul 2026",
      "AMOUNT",
      "MYR 300.00",
      "SST",
      "MYR 24.00",
      "Singapore"
    )
  end

  it "renders the total paid and positive balance due from folio transactions" do
    booking.update!(total_amount: 324.0)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 100.0)

    text = pdf_text(described_class.new(booking).generate)

    expect(text).to include("TOTAL PAID", "MYR 100.00", "BALANCE DUE", "MYR 224.00")
  end

  it "omits balance due when transactions cover the total and guest country is blank" do
    booking.update!(guest_country: nil)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 300.0)

    text = pdf_text(described_class.new(booking).generate)

    expect(text).to include("TOTAL PAID", "MYR 300.00")
    expect(text).not_to include("BALANCE DUE")
  end

  it "does not count posted room charges as payments" do
    booking.update!(total_amount: 300.0)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 300.0)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 100.0)

    text = pdf_text(described_class.new(booking).generate)

    expect(text).to include("TOTAL PAID", "MYR 100.00", "BALANCE DUE", "MYR 200.00")
  end
end
