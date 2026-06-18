require "rails_helper"

RSpec.describe EInvoice::DocumentBuilder, type: :service do
  describe "#build" do
    let(:hotel) { create(:hotel, default_currency: "MYR") }
    let(:booking) do
      create(:booking,
        hotel: hotel,
        guest_name: "John Doe",
        guest_email: "john@example.com",
        guest_phone: "+60123456789",
        check_in: 2.days.ago,
        check_out: Date.today,
        total_amount: 424.00,
        currency: "MYR"
      )
    end
    let!(:booking_room) do
      create(:booking_room,
        booking: booking,
        quantity: 2,
        subtotal: 400.00
      )
    end

    before do
      allow(Rails.application.credentials).to receive(:myinvois).and_return(
        double(
          to_h: {
            tin: "C1234567890",
            brn: "202301012345",
            name: "Jesselton Pixel Sdn Bhd",
            phone: "+60111234567",
            email: "finance@wastays.com",
            city: "Kota Kinabalu",
            postal_code: "88000",
            state_code: "12",
            address: "123 Street"
          }
        )
      )
    end

    subject { described_class.new(booking).build }

    it "returns a hash with format, document, documentHash, and codeNumber" do
      expect(subject).to include(
        format: "JSON",
        codeNumber: booking.confirmation_token
      )
      expect(subject[:document]).to be_a(String)
      expect(subject[:documentHash]).to be_a(String)
    end

    it "builds a UBL payload where line extension amount matches the math requirement" do
      decoded_json = JSON.parse(Base64.strict_decode64(subject[:document]))
      invoice = decoded_json["Invoice"].first
      line = invoice["InvoiceLine"].first

      quantity = line["InvoiceQuantity"].first["_"].to_f
      price_amount = line["Price"].first["PriceAmount"].first["_"].to_f
      line_extension_amount = line["LineExtensionAmount"].first["_"].to_f

      # LHDN math constraint validation: LineExtensionAmount = InvoiceQuantity * PriceAmount
      expect(line_extension_amount).to eq(quantity * price_amount)
    end
  end
end
