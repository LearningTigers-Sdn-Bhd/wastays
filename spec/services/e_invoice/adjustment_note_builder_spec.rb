require "rails_helper"

RSpec.describe EInvoice::AdjustmentNoteBuilder, type: :service do
  let(:hotel) { create(:hotel) }
  let!(:e_invoice_setting) do
    create(:e_invoice_setting, hotel: hotel, hotel_tin: "C9988776655", hotel_brn: "202399887766")
  end
  let(:booking) { create(:booking, hotel: hotel, payment_status: "captured", total_amount: 500.0, guest_city: "Kota Kinabalu", guest_country: "Malaysia") }
  let(:credentials_hash) do
    {
      tin: "C1234567890", brn: "202301012345", name: "Jesselton Pixel Sdn Bhd",
      phone: "+60111234567", email: "finance@wastays.com",
      city: "Kota Kinabalu", postal_code: "88000", state_code: "12",
      address: "123 Street", msic_code: "63120",
      business_description: "Web portals", country_code: "MYS"
    }
  end
  let(:original_submission) do
    create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      document_scenario: "guest_invoice",
      status: "valid",
      internal_id: "INV-001",
      uuid: "orig-uuid-123")
  end

  before do
    allow(Rails.application.credentials).to receive(:myinvois)
      .and_return(double(to_h: credentials_hash))
    create(:booking_room, booking: booking, subtotal: 500.0)
  end

  describe "debit note" do
    it "builds document with type 03" do
      builder = described_class.new(
        booking: booking,
        original_submission: original_submission,
        adjustment_amount: 80.0,
        document_type: "03"
      )
      result = builder.build
      payload = JSON.parse(Base64.strict_decode64(result[:document]))

      type_code = payload["Invoice"].first["InvoiceTypeCode"].first["_"]
      expect(type_code).to eq("03")
    end

    it "references original submission in BillingReference" do
      builder = described_class.new(
        booking: booking,
        original_submission: original_submission,
        adjustment_amount: 80.0,
        document_type: "03"
      )
      result = builder.build
      payload = JSON.parse(Base64.strict_decode64(result[:document]))
      invoice = payload["Invoice"].first

      ref = invoice["BillingReference"].first["AdditionalDocumentReference"].first["ID"].first["_"]
      expect(ref).to eq("INV-001")
    end

    it "suffixes internal_id with -DN" do
      builder = described_class.new(
        booking: booking,
        original_submission: original_submission,
        adjustment_amount: 80.0,
        document_type: "03"
      )
      result = builder.build
      expect(result[:codeNumber]).to eq("INV-001-DN")
    end

    it "uses the booking city in the buyer address" do
      builder = described_class.new(
        booking: booking,
        original_submission: original_submission,
        adjustment_amount: 80.0,
        document_type: "03"
      )
      payload = JSON.parse(Base64.strict_decode64(builder.build[:document]))
      buyer_address = payload["Invoice"].first["AccountingCustomerParty"].first["Party"].first["PostalAddress"].first

      expect(buyer_address["CityName"].first["_"]).to eq("Kota Kinabalu")
      expect(buyer_address["CountrySubentityCode"].first["_"]).to eq("12")
    end
  end

  describe "credit note" do
    it "builds document with type 02" do
      builder = described_class.new(
        booking: booking,
        original_submission: original_submission,
        adjustment_amount: 50.0,
        document_type: "02"
      )
      result = builder.build
      payload = JSON.parse(Base64.strict_decode64(result[:document]))

      type_code = payload["Invoice"].first["InvoiceTypeCode"].first["_"]
      expect(type_code).to eq("02")
    end

    it "suffixes internal_id with -CN" do
      builder = described_class.new(
        booking: booking,
        original_submission: original_submission,
        adjustment_amount: 50.0,
        document_type: "02"
      )
      result = builder.build
      expect(result[:codeNumber]).to eq("INV-001-CN")
    end
  end

  describe "validation" do
    it "raises when original submission has no UUID" do
      original_submission.update!(uuid: nil)
      expect {
        described_class.new(
          booking: booking,
          original_submission: original_submission,
          adjustment_amount: 80.0,
          document_type: "03"
        )
      }.to raise_error(ArgumentError, /UUID/)
    end

    it "raises for invalid document type" do
      expect {
        described_class.new(
          booking: booking,
          original_submission: original_submission,
          adjustment_amount: 80.0,
          document_type: "01"
        )
      }.to raise_error(ArgumentError, /02.*03/)
    end

    it "raises for non-positive adjustment amount" do
      expect {
        described_class.new(
          booking: booking,
          original_submission: original_submission,
          adjustment_amount: 0,
          document_type: "03"
        )
      }.to raise_error(ArgumentError, /positive/)
    end
  end
end
