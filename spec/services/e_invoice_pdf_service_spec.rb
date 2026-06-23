require "rails_helper"

RSpec.describe EInvoicePdfService do
  let(:hotel) { create(:hotel, name: "Seaview Hotel", city: "Kuala Lumpur", country: "Malaysia") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe King") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha Rahman",
      guest_email: "aisha@example.com",
      guest_phone: "+60123456789",
      guest_document_type: "ic",
      guest_government_id: "820916125537",
      guest_home_address: "No. 12, Jalan Ampang",
      guest_city: "Kuala Lumpur",
      guest_country: "Malaysia",
      confirmation_token: "WS-TESTEINV1",
      total_amount: 300.0,
      currency: "MYR",
      payment_status: "captured",
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0,
      check_in: Date.new(2026, 5, 1),
      check_out: Date.new(2026, 5, 3)
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      quantity: 1,
      subtotal: 300.0,
      room_type_snapshot: { "name" => "Deluxe King" }
    )
  end
  let!(:submission) do
    create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      status: "valid",
      internal_id: "SAH-300000001",
      supplier_name: "Jesselton Pixel Sdn Bhd",
      supplier_tin: "C26537918000",
      uuid: "26ZBY0Y5YVQX868FNJRC",
      submission_uid: "4MCJS3QHYW358H8CNJRC",
      long_id: "T19FQ4RT6FJDCBSENJRCRPVK10IW8KKW1782101467",
      submitted_at: Time.zone.parse("2026-06-22 12:11:00"),
      validated_at: Time.zone.parse("2026-06-22 12:11:30")
    )
  end

  subject(:result) { described_class.new(booking, submission: submission).generate }

  it "returns a valid PDF binary string" do
    expect(result).to be_a(String)
    expect(result.bytesize).to be > 3000
    expect(result.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
  end

  it "raises when booking has no valid guest e-invoice submission" do
    submission.update!(status: "invalid")

    expect { described_class.new(booking, submission: submission).generate }
      .to raise_error(ArgumentError, "Booking must have a valid guest e-invoice submission")
  end
end
