require "rails_helper"

RSpec.describe EInvoice::PayoutSelfBilledDocumentBuilder, type: :service do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:setting) { create(:e_invoice_setting, :intermediary_ready, hotel: hotel, hotel_tin: "C9988776655", hotel_brn: "202399887766") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      booking_quote: create(:booking_quote, hotel: hotel, token: nil), # Let model generate unique token
      fund_collector: "wastays",
      total_amount: 350.00,
      net_amount: 320.00,
      margin_amount: 30.00,
      check_in: 2.days.ago,
      check_out: Date.today,
      checked_out_at: Time.current
    )
  end
  let(:batch) { create(:payout_batch, hotel: hotel) }
  let(:submission) do
    create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      payout_batch: batch,
      document_scenario: "payout_self_billed_invoice",
      document_type: "11",
      submission_mode: "taxpayer",
      fund_collector: "wastays",
      supplier_name: hotel.name,
      supplier_tin: setting.hotel_tin)
  end
  let(:context) { EInvoice::SubmissionContext.for(booking, document_scenario: "payout_self_billed_invoice") }

  before do
    setting
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

  it "builds self-billed invoice with hotel as supplier and wastays as buyer" do
    result = described_class.new(submission, context: context).build
    decoded_json = JSON.parse(Base64.strict_decode64(result[:document]))
    invoice = decoded_json["Invoice"].first
    supplier = invoice.dig("AccountingSupplierParty", 0, "Party", 0)
    buyer = invoice.dig("AccountingCustomerParty", 0, "Party", 0)

    expect(invoice.dig("InvoiceTypeCode", 0, "_")).to eq("11")
    expect(supplier.dig("PartyName", 0, "Name", 0, "_")).to eq(hotel.name)
    expect(buyer.dig("PartyName", 0, "Name", 0, "_")).to eq("Jesselton Pixel Sdn Bhd")
    expect(invoice.dig("LegalMonetaryTotal", 0, "PayableAmount", 0, "_")).to eq(320.0)
  end
end
