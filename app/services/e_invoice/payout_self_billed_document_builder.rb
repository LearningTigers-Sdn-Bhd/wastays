# frozen_string_literal: true

require "digest"
require "base64"

module EInvoice
  class PayoutSelfBilledDocumentBuilder
    include PhoneFormatter

    INVOICE_TYPE_CODE = "11"
    ACCOMMODATION_CLASS_CODE = "022"

    UBL_NAMESPACES = DocumentBuilder::UBL_NAMESPACES

    def initialize(submission, context:)
      @submission = submission
      @booking = submission.booking
      @batch = submission.payout_batch || @booking.payout_batch
      @hotel = @booking.hotel
      @setting = @hotel.e_invoice_setting
      @context = context
      @creds = Rails.application.credentials.myinvois.to_h
    end

    def build
      payload_json = build_payload.to_json
      {
        format: "JSON",
        document: Base64.strict_encode64(payload_json),
        documentHash: Digest::SHA256.hexdigest(payload_json),
        codeNumber: internal_id
      }
    end

    private

    def build_payload
      document_signer.apply(UBL_NAMESPACES.merge("Invoice" => [ invoice_body ]))
    end

    # 1.1 when this hotel signs, 1.0 when it does not. See EInvoice::DocumentSigner.
    def document_version
      document_signer.document_version
    end

    def document_signer
      @document_signer ||= EInvoice::DocumentSigner.new(@setting)
    end

    def invoice_body
      {
        "ID" => [ { "_" => internal_id } ],
        "IssueDate" => [ { "_" => issue_date } ],
        "IssueTime" => [ { "_" => issue_time } ],
        "InvoiceTypeCode" => [ { "_" => INVOICE_TYPE_CODE, "listVersionID" => document_version } ],
        "DocumentCurrencyCode" => [ { "_" => currency } ],
        "TaxCurrencyCode" => [ { "_" => currency } ],
        "InvoicePeriod" => [ invoice_period ],
        "AccountingSupplierParty" => [ { "Party" => [ hotel_supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ wastays_buyer_party ] } ],
        "InvoiceLine" => [ invoice_line ],
        "TaxTotal" => [ exempt_tax_total ],
        "LegalMonetaryTotal" => [ monetary_total ]
      }
    end

    def internal_id
      [ "SBI", @booking.confirmation_token, @batch&.id || "unbatched" ].join("-")
    end

    # Issued now, not when the batch was created: LHDN rejects backdated
    # documents.
    def issue_date
      Time.current.utc.to_date.iso8601
    end

    def issue_time
      Time.current.utc.strftime("%H:%M:%SZ")
    end

    def currency
      @booking.currency.presence || @hotel.default_currency.presence || "MYR"
    end

    def invoice_period
      {
        "StartDate" => [ { "_" => @booking.check_in.to_date.iso8601 } ],
        "EndDate" => [ { "_" => @booking.check_out.to_date.iso8601 } ],
        "Description" => [ { "_" => "Self-billed payout for booking #{@booking.confirmation_token}" } ]
      }
    end

    def hotel_supplier_party
      {
        "IndustryClassificationCode" => [ { "_" => @setting.supplier_msic_code.to_s, "name" => @setting.supplier_business_description.to_s } ],
        "PartyIdentification" => [
          { "ID" => [ { "_" => @setting.hotel_tin.to_s, "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => @setting.hotel_brn.to_s, "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ {
          "CityName" => [ { "_" => @setting.supplier_city_value.to_s } ],
          "PostalZone" => [ { "_" => @setting.supplier_postal_code.to_s } ],
          "CountrySubentityCode" => [ { "_" => @setting.supplier_state_code.to_s } ],
          "AddressLine" => [
            { "Line" => [ { "_" => @setting.supplier_address_line1_value.to_s } ] },
            { "Line" => [ { "_" => @setting.supplier_address_line2_value.to_s } ] },
            { "Line" => [ { "_" => "" } ] }
          ],
          "Country" => [ { "IdentificationCode" => [ { "_" => @setting.supplier_country_code_value.to_s } ] } ]
        } ],
        "PartyLegalEntity" => [ { "CompanyID" => [ { "_" => @setting.hotel_brn.to_s } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => format_phone(@setting.supplier_contact_phone_value) } ],
          "ElectronicMail" => [ { "_" => @setting.supplier_contact_email_value.to_s } ]
        } ],
        "PartyName" => [ { "Name" => [ { "_" => @setting.supplier_name } ] } ]
      }
    end

    def wastays_buyer_party
      {
        "PartyIdentification" => [
          { "ID" => [ { "_" => wastays_tin, "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => wastays_brn, "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ {
          "CityName" => [ { "_" => @creds[:city].to_s.presence || "Kota Kinabalu" } ],
          "PostalZone" => [ { "_" => @creds[:postal_code].to_s.presence || "88000" } ],
          "CountrySubentityCode" => [ { "_" => @creds[:state_code].to_s.presence || "12" } ],
          "AddressLine" => [
            { "Line" => [ { "_" => @creds[:address].to_s.presence || "NA" } ] },
            { "Line" => [ { "_" => @creds[:address_line2].to_s } ] },
            { "Line" => [ { "_" => "" } ] }
          ],
          "Country" => [ { "IdentificationCode" => [ { "_" => @creds[:country_code].to_s.presence || "MYS" } ] } ]
        } ],
        "PartyLegalEntity" => [ { "CompanyID" => [ { "_" => wastays_brn } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => format_phone(@creds[:phone].to_s.presence || "+60111234567") } ],
          "ElectronicMail" => [ { "_" => @creds[:email].to_s.presence || "finance@wastays.com" } ]
        } ],
        "PartyName" => [ { "Name" => [ { "_" => wastays_name } ] } ]
      }
    end

    def invoice_line
      amount = payout_amount

      {
        "ID" => [ { "_" => "1" } ],
        "InvoiceQuantity" => [ { "_" => 1, "unitCode" => "NIT" } ],
        "LineExtensionAmount" => [ { "_" => amount, "currencyID" => currency } ],
        "AllowanceCharge" => [ {
          "ChargeIndicator" => [ { "_" => false } ],
          "Amount" => [ { "_" => 0, "currencyID" => currency } ]
        } ],
        "TaxTotal" => [ {
          "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
          "TaxSubtotal" => [ exempt_tax_subtotal(amount) ]
        } ],
        "Item" => [ {
          "CommodityClassification" => [ {
            "ItemClassificationCode" => [ { "_" => ACCOMMODATION_CLASS_CODE, "listID" => "CLASS" } ]
          } ],
          "Description" => [ { "_" => "Self-billed payout for booking #{@booking.confirmation_token}" } ],
          "OriginCountry" => [ { "IdentificationCode" => [ { "_" => "MYS" } ] } ]
        } ],
        "Price" => [ { "PriceAmount" => [ { "_" => amount, "currencyID" => currency } ] } ],
        "ItemPriceExtension" => [ { "Amount" => [ { "_" => amount, "currencyID" => currency } ] } ]
      }
    end

    def exempt_tax_total
      amount = payout_amount
      {
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "TaxSubtotal" => [ exempt_tax_subtotal(amount) ]
      }
    end

    def exempt_tax_subtotal(amount)
      {
        "TaxableAmount" => [ { "_" => amount, "currencyID" => currency } ],
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "TaxCategory" => [ {
          "ID" => [ { "_" => "E" } ],
          "TaxExemptionReason" => [ { "_" => "Pending business confirmation for payout self-billed tax basis" } ],
          "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
        } ]
      }
    end

    def monetary_total
      amount = payout_amount
      {
        "LineExtensionAmount" => [ { "_" => amount, "currencyID" => currency } ],
        "TaxExclusiveAmount" => [ { "_" => amount, "currencyID" => currency } ],
        "TaxInclusiveAmount" => [ { "_" => amount, "currencyID" => currency } ],
        "AllowanceTotalAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "ChargeTotalAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "PayableRoundingAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "PayableAmount" => [ { "_" => amount, "currencyID" => currency } ]
      }
    end

    def payout_amount
      @booking.net_amount.to_d.to_f.round(2)
    end

    def wastays_tin
      @creds[:tin].to_s.presence || raise(ArgumentError, "myinvois.tin not configured in credentials")
    end

    def wastays_brn
      @creds[:brn].to_s.presence || raise(ArgumentError, "myinvois.brn not configured in credentials")
    end

    def wastays_name
      @creds[:name].to_s.presence || "Jesselton Pixel Sdn Bhd"
    end
  end
end
