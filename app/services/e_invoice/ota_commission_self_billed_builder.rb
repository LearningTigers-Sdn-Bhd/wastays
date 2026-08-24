# frozen_string_literal: true

require "digest"
require "base64"

module EInvoice
  # An OTA's commission is a service bought from an overseas company - Agoda in
  # Singapore, Booking.com in the Netherlands. LHDN has no e-invoice from them
  # to match against, so the hotel issues a self-billed e-invoice for the
  # importation of services in order to deduct the expense.
  #
  # The hotel is the buyer and the issuer; the OTA is the supplier.
  class OtaCommissionSelfBilledBuilder
    include PhoneFormatter

    INVOICE_TYPE_CODE = "11" # self-billed invoice
    # LHDN's placeholder identifiers for a supplier outside Malaysia.
    FOREIGN_SUPPLIER_TIN = "EI00000000030"
    FOREIGN_SUPPLIER_BRN = "NA"
    FOREIGN_SUPPLIER_MSIC = "00000"
    FOREIGN_SUPPLIER_MSIC_NAME = "NOT APPLICABLE"
    COMMISSION_CLASS_CODE = "022"
    DEFAULT_CURRENCY = "MYR"

    UBL_NAMESPACES = DocumentBuilder::UBL_NAMESPACES

    def initialize(hotel:, source:, period_start:, amount:, booking_count:)
      @hotel = hotel
      @setting = hotel.e_invoice_setting
      @source = source
      @period_start = period_start.to_date
      @amount = amount.to_d
      @booking_count = booking_count
    end

    def build
      raise ArgumentError, "Hotel e-invoice setting is missing." unless @setting
      raise ArgumentError, "Commission amount must be positive." unless @amount.positive?

      payload_json = build_payload.to_json
      {
        format: "JSON",
        document: Base64.strict_encode64(payload_json),
        documentHash: Digest::SHA256.hexdigest(payload_json),
        codeNumber: internal_id
      }
    end

    def internal_id
      "SB-#{@source.key.upcase}-#{@period_start.strftime('%Y%m')}-#{@hotel.id}"
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
        "IssueDate" => [ { "_" => issue_date.iso8601 } ],
        "IssueTime" => [ { "_" => Time.current.utc.strftime("%H:%M:%SZ") } ],
        "InvoiceTypeCode" => [ { "_" => INVOICE_TYPE_CODE, "listVersionID" => document_version } ],
        "DocumentCurrencyCode" => [ { "_" => DEFAULT_CURRENCY } ],
        "TaxCurrencyCode" => [ { "_" => DEFAULT_CURRENCY } ],
        "InvoicePeriod" => [ {
          "StartDate" => [ { "_" => @period_start.iso8601 } ],
          "EndDate" => [ { "_" => @period_start.end_of_month.iso8601 } ],
          "Description" => [ { "_" => "Commission period" } ]
        } ],
        "AccountingSupplierParty" => [ { "Party" => [ ota_supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ hotel_buyer_party ] } ],
        "InvoiceLine" => [ invoice_line ],
        "TaxTotal" => [ exempt_tax_total ],
        "LegalMonetaryTotal" => [ monetary_total ]
      }
    end

    # Issued now; the month it covers is carried by InvoicePeriod. Dating it to
    # the end of the period would backdate the document, which LHDN rejects.
    def issue_date
      Time.current.utc.to_date
    end

    def ota_supplier_party
      {
        "IndustryClassificationCode" => [ { "_" => FOREIGN_SUPPLIER_MSIC, "name" => FOREIGN_SUPPLIER_MSIC_NAME } ],
        "PartyIdentification" => [
          { "ID" => [ { "_" => FOREIGN_SUPPLIER_TIN, "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => FOREIGN_SUPPLIER_BRN, "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ {
          "CityName" => [ { "_" => "NA" } ],
          "PostalZone" => [ { "_" => "NA" } ],
          "CountrySubentityCode" => [ { "_" => MalaysiaStates::NOT_APPLICABLE } ],
          "AddressLine" => [
            { "Line" => [ { "_" => "NA" } ] },
            { "Line" => [ { "_" => "" } ] },
            { "Line" => [ { "_" => "" } ] }
          ],
          "Country" => [ { "IdentificationCode" => [ country_identification_code(supplier_country_code) ] } ]
        } ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => supplier_legal_name } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => "NA" } ],
          "ElectronicMail" => [ { "_" => "NA" } ]
        } ],
        "PartyName" => [ { "Name" => [ { "_" => supplier_legal_name } ] } ]
      }
    end

    def hotel_buyer_party
      {
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
          "Country" => [ { "IdentificationCode" => [ country_identification_code(@setting.supplier_country_code_value.to_s) ] } ]
        } ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => @setting.supplier_name } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => format_phone(@setting.supplier_contact_phone_value) } ],
          "ElectronicMail" => [ { "_" => @setting.supplier_contact_email_value.to_s } ]
        } ]
      }
    end

    def invoice_line
      {
        "ID" => [ { "_" => "1" } ],
        "InvoicedQuantity" => [ { "_" => 1, "unitCode" => "C62" } ],
        "LineExtensionAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ],
        "AllowanceCharge" => [ {
          "ChargeIndicator" => [ { "_" => false } ],
          "Amount" => [ { "_" => 0, "currencyID" => DEFAULT_CURRENCY } ]
        } ],
        "TaxTotal" => [ {
          "TaxAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
          "TaxSubtotal" => [ exempt_tax_subtotal ]
        } ],
        "Item" => [ {
          "CommodityClassification" => [ {
            "ItemClassificationCode" => [ { "_" => COMMISSION_CLASS_CODE, "listID" => "CLASS" } ]
          } ],
          "Description" => [ { "_" => description } ],
          "OriginCountry" => [ { "IdentificationCode" => [ { "_" => supplier_country_code } ] } ]
        } ],
        "Price" => [ { "PriceAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ] } ],
        "ItemPriceExtension" => [ { "Amount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ] } ]
      }
    end

    def description
      "#{supplier_legal_name} commission for #{@period_start.strftime('%B %Y')} " \
        "(#{@booking_count} #{'booking'.pluralize(@booking_count)})"
    end

    def exempt_tax_total
      {
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxSubtotal" => [ exempt_tax_subtotal ]
      }
    end

    def exempt_tax_subtotal
      {
        "TaxableAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxCategory" => [ {
          "ID" => [ { "_" => "E" } ],
          "TaxExemptionReason" => [ { "_" => "Exempt - imported service" } ],
          "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
        } ]
      }
    end

    def monetary_total
      {
        "LineExtensionAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxExclusiveAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxInclusiveAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ],
        "AllowanceTotalAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "ChargeTotalAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "PayableAmount" => [ { "_" => rounded_amount, "currencyID" => DEFAULT_CURRENCY } ]
      }
    end

    def rounded_amount
      @amount.to_f.round(2)
    end

    def supplier_legal_name
      @source.legal_name.presence || @source.label
    end

    def supplier_country_code
      @source.tax_country_code.presence || "SGP"
    end

    def country_identification_code(code)
      { "_" => code, "listID" => "ISO3166-1", "listAgencyID" => "6" }
    end
  end
end
