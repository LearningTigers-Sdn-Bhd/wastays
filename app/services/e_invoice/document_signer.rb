# frozen_string_literal: true

require "digest"
require "base64"
require "openssl"

module EInvoice
  # LHDN document version 1.1 carries a digital signature; 1.0 does not.
  #
  # The document is always built in the 1.1 shape. When a hotel has not enabled
  # signing, the signature block is dropped and the document declares itself as
  # 1.0 - which is what LHDN accepts today. When signing is switched on, the
  # same document gains the block and declares 1.1. Nothing else changes, and
  # in particular the submission endpoint is the same either way: the version
  # is a property of the document, not of the API.
  #
  # This exists so that the day LHDN mandates 1.1, the change is a setting per
  # hotel rather than a rewrite of every builder.
  class DocumentSigner
    class ConfigurationError < StandardError; end

    VERSION_UNSIGNED = "1.0"
    VERSION_SIGNED = "1.1"

    SIGNATURE_ID = "urn:oasis:names:specification:ubl:signature:Invoice"
    SIGNATURE_METHOD = "urn:oasis:names:specification:ubl:dsig:enveloped:xades"

    def initialize(setting)
      @setting = setting
    end

    def enabled?
      @setting&.signature_enabled?
    end

    def document_version
      enabled? ? VERSION_SIGNED : VERSION_UNSIGNED
    end

    # Signing covers the document as submitted, so it runs over the finished
    # payload rather than being woven through each builder.
    def apply(payload)
      return payload unless enabled?

      ensure_signing_material!

      invoice = payload["Invoice"].first
      document_digest = digest_for(payload)

      invoice["UBLExtensions"] = [ ubl_extensions(document_digest) ]
      invoice["Signature"] = [ {
        "ID" => [ { "_" => SIGNATURE_ID } ],
        "SignatureMethod" => [ { "_" => SIGNATURE_METHOD } ]
      } ]

      payload
    end

    private

    def ensure_signing_material!
      return if @setting.signing_certificate.present? && @setting.signing_private_key.present?

      raise ConfigurationError,
        "Signing is switched on for this hotel but its certificate and private key are missing."
    end

    # LHDN digests the document with the signature-related properties removed,
    # which is what the payload is before anything is applied.
    def digest_for(payload)
      Digest::SHA256.base64digest(payload.to_json)
    end

    def signed_properties_digest(document_digest)
      Digest::SHA256.base64digest(document_digest)
    end

    def signature_value(document_digest)
      key = OpenSSL::PKey::RSA.new(@setting.signing_private_key)
      Base64.strict_encode64(key.sign(OpenSSL::Digest.new("SHA256"), document_digest))
    rescue OpenSSL::PKey::PKeyError => e
      raise ConfigurationError, "This hotel's signing key could not be read: #{e.message}"
    end

    def certificate
      @certificate ||= OpenSSL::X509::Certificate.new(@setting.signing_certificate)
    rescue OpenSSL::X509::CertificateError => e
      raise ConfigurationError, "This hotel's signing certificate could not be read: #{e.message}"
    end

    def ubl_extensions(document_digest)
      {
        "UBLExtension" => [ {
          "ExtensionURI" => [ { "_" => "urn:oasis:names:specification:ubl:dsig:enveloped:xades" } ],
          "ExtensionContent" => [ {
            "UBLDocumentSignatures" => [ {
              "SignatureInformation" => [ {
                "ID" => [ { "_" => "urn:oasis:names:specification:ubl:signature:1" } ],
                "ReferencedSignatureID" => [ { "_" => SIGNATURE_ID } ],
                "Signature" => [ signature_block(document_digest) ]
              } ]
            } ]
          } ]
        } ]
      }
    end

    def signature_block(document_digest)
      {
        "Id" => "signature",
        "SignedInfo" => [ {
          "SignatureMethod" => [ { "_" => "", "Algorithm" => "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" } ],
          "Reference" => [
            {
              "Id" => "id-doc-signed-data",
              "URI" => "",
              "DigestMethod" => [ { "_" => "", "Algorithm" => "http://www.w3.org/2001/04/xmlenc#sha256" } ],
              "DigestValue" => [ { "_" => document_digest } ]
            },
            {
              "Id" => "id-xades-signed-props",
              "URI" => "#id-xades-signed-props",
              "DigestMethod" => [ { "_" => "", "Algorithm" => "http://www.w3.org/2001/04/xmlenc#sha256" } ],
              "DigestValue" => [ { "_" => signed_properties_digest(document_digest) } ]
            }
          ]
        } ],
        "SignatureValue" => [ { "_" => signature_value(document_digest) } ],
        "KeyInfo" => [ {
          "X509Data" => [ {
            "X509Certificate" => [ { "_" => Base64.strict_encode64(certificate.to_der) } ],
            "X509SubjectName" => [ { "_" => certificate.subject.to_s } ],
            "X509IssuerSerial" => [ {
              "X509IssuerName" => [ { "_" => certificate.issuer.to_s } ],
              "X509SerialNumber" => [ { "_" => certificate.serial.to_s } ]
            } ]
          } ]
        } ]
      }
    end
  end
end
