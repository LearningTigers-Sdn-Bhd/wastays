require "rails_helper"

RSpec.describe EInvoice::GuestStatusPayload do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel) }

  def call(download_url: "/guest/bookings/1/e_invoice")
    described_class.new(booking: booking, download_url: download_url).call
  end

  it "reports idle when nothing was requested" do
    payload = call

    expect(payload[:status]).to eq("idle")
    expect(payload[:download_url]).to be_nil
    expect(payload[:document_label]).to be_nil
  end

  it "reports ready with the download URL the caller gave" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", document_type: "01")

    payload = call

    expect(payload[:status]).to eq("ready")
    expect(payload[:message]).to eq("Your e-invoice is ready.")
    expect(payload[:download_url]).to eq("/guest/bookings/1/e_invoice")
  end

  it "names an adjustment differently" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "valid", document_type: "02")

    expect(call[:message]).to eq("Your updated e-invoice is ready.")
  end

  it "reports processing while a submission is pending" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "pending", document_type: "01")

    payload = call

    expect(payload[:status]).to eq("processing")
    expect(payload[:download_url]).to be_nil
  end

  it "gives the failure message from the submission" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "invalid",
      document_type: "01",
      error_details: { "rejected" => { "error" => { "details" => [ { "message" => "Buyer TIN is not valid." } ] } } })

    payload = call

    expect(payload[:status]).to eq("failed")
    expect(payload[:message]).to eq("Buyer TIN is not valid.")
  end

  it "falls back to a plain message when the submission carries no detail" do
    create(:e_invoice_submission, hotel: hotel, booking: booking, status: "invalid", document_type: "01")

    expect(call[:message]).to include("could not generate the e-invoice")
  end
end
