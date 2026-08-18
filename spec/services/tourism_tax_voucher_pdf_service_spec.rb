require "rails_helper"

RSpec.describe TourismTaxVoucherPdfService do
  let(:hotel) { create(:hotel, name: "Seaview Hotel", city: "Kuala Lumpur", country: "Malaysia", tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
  let(:staff) { create(:user, name: "Trial") }

  context "before tourism tax has been collected" do
    let(:booking) do
      create(:booking,
        hotel: hotel,
        guest_name: "Aisha Rahman",
        guest_country: "Singapore",
        tourism_tax_amount: 10.0,
        tax_lines: [ { "type" => "tourism_tax", "amount" => 10.0 } ])
    end

    it "returns a valid PDF binary string" do
      result = described_class.new(booking: booking, printed_by: staff).generate
      reader = PDF::Reader.new(StringIO.new(result))

      expect(result).to be_a(String)
      expect(result.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
      expect(result.bytesize).to be > 1500
      expect(reader.pages.size).to eq(2)
      expect(reader.pages.first.text).to include(
        "TOURISM TAX VOUCHER", "GUEST COPY", "PAYABLE", "Not yet collected",
        "GUEST SIGNATURE", "AUTHORISED SIGNATURE", "It is not evidence of payment."
      )
      expect(reader.pages.last.text).to include(
        "TOURISM TAX VOUCHER", "HOTEL COPY", "PAYABLE", "Not yet collected",
        "GUEST SIGNATURE", "AUTHORISED SIGNATURE", "It is not evidence of payment."
      )
    end
  end

  context "after tourism tax has been collected" do
    let(:booking) do
      create(:booking,
        hotel: hotel,
        guest_name: "Aisha Rahman",
        guest_country: "Singapore",
        tourism_tax_collected: true,
        tourism_tax_amount: 10.0,
        tax_lines: [ { "type" => "tourism_tax", "amount" => 10.0 } ])
    end

    it "returns a valid PDF binary string" do
      result = described_class.new(booking: booking, printed_by: staff).generate
      reader = PDF::Reader.new(StringIO.new(result))

      expect(result).to be_a(String)
      expect(result.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
      expect(result.bytesize).to be > 1500
      expect(reader.pages.size).to eq(2)
      expect(reader.pages.first.text).to include("TOURISM TAX VOUCHER", "GUEST COPY", "COLLECTED")
      expect(reader.pages.last.text).to include("TOURISM TAX VOUCHER", "HOTEL COPY", "COLLECTED")
    end
  end
end
