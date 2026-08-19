require "rails_helper"

RSpec.describe EInvoice::ConsolidatedBatchBuilder, type: :service do
  let(:hotel) { create(:hotel) }
  let!(:e_invoice_setting) { create(:e_invoice_setting, hotel: hotel, enabled: true) }
  let(:credentials_hash) do
    {
      tin: "C1234567890", brn: "202301012345", name: "Jesselton Pixel Sdn Bhd",
      phone: "+60111234567", email: "finance@wastays.com",
      city: "Kota Kinabalu", postal_code: "88000", state_code: "12",
      address: "123 Street", msic_code: "63120",
      business_description: "Web portals", country_code: "MYS"
    }
  end

  before do
    allow(Rails.application.credentials).to receive(:myinvois)
      .and_return(double(to_h: credentials_hash))
  end

  describe "#build_for_bookings" do
    let(:month_start) { Date.new(2026, 1, 1) }

    let!(:booking1) do
      create(:booking, hotel: hotel, total_amount: 200.0, payment_status: "captured", currency: "MYR")
    end
    let!(:booking2) do
      create(:booking, hotel: hotel, total_amount: 350.0, payment_status: "captured", currency: "MYR")
    end

    before do
      create(:booking_room, booking: booking1, subtotal: 200.0)
      create(:booking_room, booking: booking2, subtotal: 350.0)
    end

    it "builds a valid document hash with JSON format" do
      result = described_class.new(hotel: hotel).build_for_bookings([ booking1, booking2 ], month_start: month_start)

      expect(result[:format]).to eq("JSON")
      expect(result[:document]).to be_present
      expect(result[:documentHash]).to be_present
      expect(result[:codeNumber]).to start_with("CONS-")
    end

    it "uses the generic consolidated buyer" do
      result = described_class.new(hotel: hotel).build_for_bookings([ booking1 ], month_start: month_start)
      payload = JSON.parse(Base64.strict_decode64(result[:document]))

      buyer = payload["Invoice"].first["AccountingCustomerParty"].first["Party"].first
      tin = buyer["PartyIdentification"].find { |pid| pid["ID"].first["schemeID"] == "TIN" }["ID"].first["_"]
      name = buyer["PartyLegalEntity"].first["RegistrationName"].first["_"]

      expect(tin).to eq("EI00000000010")
      expect(name).to eq("General Public")
    end

    it "includes one invoice line per booking" do
      result = described_class.new(hotel: hotel).build_for_bookings([ booking1, booking2 ], month_start: month_start)
      payload = JSON.parse(Base64.strict_decode64(result[:document]))

      lines = payload["Invoice"].first["InvoiceLine"]
      expect(lines.length).to eq(2)
    end

    it "totals correctly from all bookings" do
      result = described_class.new(hotel: hotel).build_for_bookings([ booking1, booking2 ], month_start: month_start)
      payload = JSON.parse(Base64.strict_decode64(result[:document]))

      payable = payload["Invoice"].first["LegalMonetaryTotal"].first["PayableAmount"].first["_"]
      expect(payable).to eq(550.0)
    end

    it "raises error when no bookings provided" do
      expect {
        described_class.new(hotel: hotel).build_for_bookings([], month_start: month_start)
      }.to raise_error(ArgumentError, /No bookings/)
    end

    it "uses hotel supplier details when built with intermediary context" do
      hotel.e_invoice_setting.update!(
        intermediary_enabled: true,
        supplier_msic_code: "55101",
        supplier_business_description: "Hotel accommodation services",
        supplier_address_line1: "1 Jalan Hotel",
        supplier_city: "Kota Kinabalu",
        supplier_postal_code: "88000",
        supplier_state_code: "12",
        supplier_contact_phone: "+6088123456",
        supplier_contact_email: "finance@hotel.test"
      )
      booking1.update!(fund_collector: "hotel")
      context = EInvoice::SubmissionContext.for(booking1, document_scenario: "hotel_intermediary_guest_invoice")

      result = described_class.new(hotel: hotel, context: context).build_for_bookings([ booking1 ], month_start: month_start)
      payload = JSON.parse(Base64.strict_decode64(result[:document]))

      supplier = payload["Invoice"].first["AccountingSupplierParty"].first["Party"].first
      tin = supplier["PartyIdentification"].find { |pid| pid["ID"].first["schemeID"] == "TIN" }["ID"].first["_"]
      name = supplier["PartyLegalEntity"].first["RegistrationName"].first["_"]

      expect(tin).to eq(hotel.e_invoice_setting.hotel_tin)
      expect(name).to eq(hotel.e_invoice_setting.supplier_name)
    end
  end
end
