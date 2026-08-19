# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::DocumentSigner do
  let(:hotel) { create(:hotel) }

  # A throwaway self-signed pair, so the signing path is genuinely exercised
  # rather than stubbed.
  let(:key) { OpenSSL::PKey::RSA.new(2048) }
  let(:certificate) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1234
    cert.subject = OpenSSL::X509::Name.parse("/CN=Test Hotel")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.current
    cert.not_after = Time.current + 1.year
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def payload
    { "Invoice" => [ { "ID" => [ { "_" => "INV-1" } ] } ] }
  end

  context "when the hotel has not switched signing on" do
    let(:setting) { create(:e_invoice_setting, hotel: hotel, signature_enabled: false) }

    it "declares the document as 1.0" do
      expect(described_class.new(setting).document_version).to eq("1.0")
    end

    it "leaves the document unsigned" do
      result = described_class.new(setting).apply(payload)

      expect(result["Invoice"].first).not_to have_key("UBLExtensions")
      expect(result["Invoice"].first).not_to have_key("Signature")
    end
  end

  context "when the hotel signs its documents" do
    let(:setting) do
      create(:e_invoice_setting, hotel: hotel,
        signature_enabled: true,
        signing_certificate: certificate.to_pem,
        signing_private_key: key.to_pem)
    end

    it "declares the document as 1.1" do
      expect(described_class.new(setting).document_version).to eq("1.1")
    end

    it "adds the signature block and the reference to it" do
      invoice = described_class.new(setting).apply(payload)["Invoice"].first

      expect(invoice).to have_key("UBLExtensions")
      expect(invoice.dig("Signature", 0, "ID", 0, "_")).to eq(described_class::SIGNATURE_ID)
    end

    it "signs with the hotel's key, verifiably" do
      invoice = described_class.new(setting).apply(payload)["Invoice"].first
      signature = invoice.dig("UBLExtensions", 0, "UBLExtension", 0, "ExtensionContent", 0,
        "UBLDocumentSignatures", 0, "SignatureInformation", 0, "Signature", 0)

      digest = signature.dig("SignedInfo", 0, "Reference", 0, "DigestValue", 0, "_")
      signature_value = Base64.strict_decode64(signature.dig("SignatureValue", 0, "_"))

      expect(key.public_key.verify(OpenSSL::Digest.new("SHA256"), signature_value, digest)).to be(true)
    end

    it "carries the certificate for LHDN to check against" do
      invoice = described_class.new(setting).apply(payload)["Invoice"].first
      signature = invoice.dig("UBLExtensions", 0, "UBLExtension", 0, "ExtensionContent", 0,
        "UBLDocumentSignatures", 0, "SignatureInformation", 0, "Signature", 0)
      embedded = signature.dig("KeyInfo", 0, "X509Data", 0, "X509Certificate", 0, "_")

      expect(Base64.strict_decode64(embedded)).to eq(certificate.to_der)
    end
  end

  # The setting itself refuses this combination, so reaching the signer without
  # signing material means something bypassed validation. Falling back to
  # unsigned silently would file documents LHDN rejects, so it fails loudly.
  it "refuses to build when signing is on but no key was uploaded" do
    setting = create(:e_invoice_setting, hotel: hotel)
    setting.update_column(:signature_enabled, true)

    expect { described_class.new(setting).apply(payload) }
      .to raise_error(described_class::ConfigurationError, /certificate and private key are missing/)
  end

  it "will not let a hotel switch signing on without a certificate" do
    setting = build(:e_invoice_setting, hotel: hotel, signature_enabled: true)

    expect(setting).not_to be_valid
    expect(setting.errors[:signature_enabled].join).to match(/signing certificate/)
  end
end
