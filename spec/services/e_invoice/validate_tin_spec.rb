# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::ValidateTin do
  let(:hotel) { create(:hotel) }
  let(:setting) { create(:e_invoice_setting, hotel: hotel) }
  let(:client) { instance_double(MyInvois::MockClient) }

  before { allow(MyInvois::ClientFactory).to receive(:build).and_return(client) }

  def validate(tin: "IG12345678901", id_value: "880101015432", document_type: "ic")
    described_class.call(tin: tin, id_value: id_value, document_type: document_type, setting: setting)
  end

  it "confirms a TIN that matches the identity given" do
    allow(client).to receive(:validate_tin).and_return({ "tin" => "IG12345678901", "status" => "Valid" })

    expect(validate).to be_valid
  end

  it "reports a TIN LHDN does not recognise for that identity" do
    allow(client).to receive(:validate_tin).and_return({ "tin" => "IG1", "status" => "Invalid" })

    result = validate
    expect(result).to be_invalid
    expect(result.message).to include("IC number")
  end

  # LHDN answers a mismatch with a 404 rather than a body.
  it "treats a 404 as a mismatch, since that is a real answer" do
    allow(client).to receive(:validate_tin)
      .and_raise(MyInvois::Client::ApiError.new("Not found", code: "404"))

    expect(validate).to be_invalid
  end

  # Checking a tax number must never stop someone checking in.
  it "stays out of the way when LHDN is unreachable" do
    allow(client).to receive(:validate_tin)
      .and_raise(MyInvois::Client::ApiError.new("Service unavailable", code: "503"))

    result = validate
    expect(result).to be_unknown
    expect(result.message).to include("filed")
  end

  # Confirmed against LHDN preprod: a match is a 200 with an empty body, not a
  # JSON payload with a status field. Reaching here at all means LHDN did not
  # reject the pairing.
  it "treats an empty response as a match, since that is what LHDN sends for one" do
    allow(client).to receive(:validate_tin).and_return({})

    expect(validate).to be_valid
  end

  it "sends the identity type LHDN expects for a passport" do
    allow(client).to receive(:validate_tin).and_return({ "status" => "Valid" })

    validate(document_type: "passport")

    expect(client).to have_received(:validate_tin).with("IG12345678901", id_type: "PASSPORT", id_value: "880101015432")
  end

  it "falls back to a business registration number for a company" do
    allow(client).to receive(:validate_tin).and_return({ "status" => "Valid" })

    validate(document_type: nil)

    expect(client).to have_received(:validate_tin).with(anything, hash_including(id_type: "BRN"))
  end

  it "strips punctuation from an IC before asking" do
    allow(client).to receive(:validate_tin).and_return({ "status" => "Valid" })

    validate(id_value: "880101-01-5432")

    expect(client).to have_received(:validate_tin).with(anything, hash_including(id_value: "880101015432"))
  end

  it "asks for the missing piece rather than calling LHDN with half of it" do
    allow(client).to receive(:validate_tin)

    expect(validate(tin: "").message).to include("Enter a tax number")
    expect(validate(id_value: "").message).to include("IC, passport or business registration")
    expect(client).not_to have_received(:validate_tin)
  end
end
