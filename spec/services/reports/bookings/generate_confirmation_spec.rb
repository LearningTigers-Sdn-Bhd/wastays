require "rails_helper"

RSpec.describe Reports::Bookings::GenerateConfirmation do
  let(:hotel) { create(:hotel, name: "Seaview Hotel", city: "Kuala Lumpur", country: "Malaysia") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe King") }
  let(:currency) { "MYR" }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Aisha Rahman",
      guest_email: "aisha@example.com",
      guest_phone: "+60123456789",
      confirmation_token: "WS-TESTREC1",
      total_amount: 348.0,
      currency: currency,
      payment_status: "captured",
      tourism_tax_applied: false,
      tourism_tax_amount: 0.0,
      tax_lines: [ { "name" => "SST", "amount" => "48.00" } ],
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

  def pdf_text(pdf) = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

  it "returns a valid PDF binary string" do
    expect(result).to be_a(String)
    expect(result.bytesize).to be > 2000
    expect(result.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
  end

  it "names itself a confirmation and leads on the guest's confirmation code" do
    text = pdf_text(result)

    expect(text).to match(/booking confirmation/i)
    expect(text).to include("WS-TESTREC1")
  end

  it "carries the hotel's identity rather than the platform's" do
    text = pdf_text(result)

    expect(text).to include("Seaview Hotel")
    expect(text).not_to include("hello@wastays.com")
  end

  it "prints the room, the taxes in the total, and the booking total" do
    text = pdf_text(result)

    expect(text).to include("Deluxe King")
    expect(text).to include("SST")
    expect(text).to include("Booking total")
    expect(text).to include("348.00")
  end

  it "states that it is not a payment receipt" do
    expect(pdf_text(result)).to include("not a payment receipt")
  end

  context "when the hotel does not bill in ringgit" do
    let(:currency) { "SGD" }

    it "labels amounts in the booking's own currency" do
      text = pdf_text(result)

      expect(text).to include("SGD")
      expect(text).not_to include("MYR")
    end
  end

  context "when tourism tax applies" do
    before do
      booking.update!(
        tourism_tax_applied: true,
        tourism_tax_amount: 20.0,
        tax_lines: [ { "name" => "SST", "amount" => "48.00" }, { "name" => "Tourism Tax", "type" => "tourism_tax", "amount" => "20.00" } ]
      )
    end

    # The booking total excludes tourism tax, so listing it as a line item would leave the
    # rows summing to more than the total printed under them.
    it "keeps it out of the line items and discloses it separately" do
      text = pdf_text(result)

      expect(text).to include("Excluded from booking total")
      expect(text.scan("Tourism Tax").size).to eq(0)
    end
  end

  context "with empty room_type_snapshot" do
    before { booking_room.update!(room_type_snapshot: {}) }

    it "falls back to room_type name and generates without error" do
      expect(pdf_text(result)).to include("Deluxe King")
    end
  end
end
