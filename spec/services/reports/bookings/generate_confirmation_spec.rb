require "rails_helper"

RSpec.describe Reports::Bookings::GenerateConfirmation do
  let(:hotel) { create(:hotel, name: "Seaview Hotel", city: "Kuala Lumpur", country: "Malaysia") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe King") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha Rahman",
      guest_email: "aisha@example.com",
      guest_phone: "+60123456789",
      confirmation_token: "WS-TESTREC1",
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
      subtotal: 300.0,
      room_type_snapshot: { "name" => "Deluxe King" }
    )
  end

  subject(:result) { described_class.new(booking).generate }

  it "returns a valid PDF binary string" do
    expect(result).to be_a(String)
    expect(result.bytesize).to be > 2000
    expect(result.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
  end

  context "with empty room_type_snapshot" do
    before { booking_room.update!(room_type_snapshot: {}) }

    it "falls back to room_type name and generates without error" do
      expect { result }.not_to raise_error
    end
  end
end
