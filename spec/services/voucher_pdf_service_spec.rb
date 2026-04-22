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
    create(:booking_room, booking: booking, room_type: room_type, quantity: 1, subtotal: 300.0, room_type_snapshot: { "name" => "Deluxe" })
  end

  it "generates a valid PDF binary" do
    pdf = described_class.new(booking).generate

    expect(pdf).to be_a(String)
    expect(pdf.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
    expect(pdf.bytesize).to be > 1500
  end
end
