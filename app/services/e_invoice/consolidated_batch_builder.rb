# frozen_string_literal: true

require "digest"
require "base64"
require "securerandom"

module EInvoice
  class ConsolidatedBatchBuilder
    include PhoneFormatter

    INVOICE_TYPE_CODE        = "01"
    ACCOMMODATION_CLASS_CODE = "022"
    GENERAL_CONSUMER_TIN     = "EI00000000010"
    GENERAL_CONSUMER_NAME    = "General Public"
    DEFAULT_CURRENCY         = "MYR"
    ORIGIN_COUNTRY_CODE      = "MYS"
    COUNTRY_LIST_ID          = "ISO3166-1"
    COUNTRY_LIST_AGENCY_ID   = "6"
    UNIT_CODE_EACH           = "C62"
    NA_VALUE                 = "NA"
    ZERO_ALLOWANCE_CHARGE    = {
      "ChargeIndicator" => [ { "_" => false } ],
      "Amount" => [ { "_" => 0, "currencyID" => DEFAULT_CURRENCY } ]
    }.freeze

    UBL_NAMESPACES = {
      "_D" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
      "_A" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
      "_B" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
    }.freeze

    def initialize(hotel:, context: nil)
      @hotel = hotel
      @creds = Rails.application.credentials.myinvois.to_h
      @context = context
      @setting = hotel.e_invoice_setting
      validate_required_data!
    end

    def build_for_bookings(bookings, month_start:)
      raise ArgumentError, "No bookings provided" if bookings.blank?

      @bookings = bookings
      @month_start = month_start.to_date

      payload_json = build_payload.to_json
      internal_id = generate_internal_id
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
        "DocumentCurrencyCode" => [ { "_" => DEFAULT_CURRENCY } ],
        "TaxCurrencyCode" => [ { "_" => DEFAULT_CURRENCY } ],
        "InvoicePeriod" => [ invoice_period ],
        "AccountingSupplierParty" => [ { "Party" => [ supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ consolidated_buyer_party ] } ],
        "InvoiceLine" => invoice_lines,
        "TaxTotal" => [ tax_total_block ],
        "LegalMonetaryTotal" => [ monetary_total ]
      }
    end

    def internal_id
      @internal_id ||= generate_internal_id
    end

    def generate_internal_id
      "CONS-#{@hotel.id}-#{@month_start.strftime("%Y%m")}-#{SecureRandom.hex(3).upcase}"
    end

    def issue_date
      Time.current.to_date.iso8601
    end

    def issue_time
      Time.current.utc.strftime("%H:%M:%SZ")
    end

    def invoice_period
      month_end = @month_start.end_of_month
      {
        "StartDate" => [ { "_" => @month_start.iso8601 } ],
        "EndDate" => [ { "_" => month_end.iso8601 } ],
        "Description" => [ { "_" => "Monthly consolidated e-invoice" } ]
      }
    end

    def supplier_party
      {
        "IndustryClassificationCode" => [ { "_" => supplier[:msic_code], "name" => supplier[:business_description] } ],
        "PartyIdentification" => [
          { "ID" => [ { "_" => supplier[:tin], "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => supplier[:brn], "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ supplier_address ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => supplier[:name] } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => supplier[:phone] } ],
          "ElectronicMail" => [ { "_" => supplier[:email] } ]
        } ]
      }
    end

    def supplier
      # Consolidated batches are the hotel's own filing too - WAStays never
      # appears as supplier on a guest e-invoice.
      @supplier ||= hotel_supplier_profile
    end

    def supplier_address
      {
        "CityName" => [ { "_" => supplier[:city] } ],
        "PostalZone" => [ { "_" => supplier[:postal_code] } ],
        "CountrySubentityCode" => [ { "_" => supplier[:state_code] } ],
        "AddressLine" => [
          { "Line" => [ { "_" => supplier[:address_line1] } ] },
          { "Line" => [ { "_" => "" } ] },
          { "Line" => [ { "_" => "" } ] }
        ],
        "Country" => [ { "IdentificationCode" => [ country_identification_code(supplier[:country_code]) ] } ]
      }
    end

    def consolidated_buyer_party
      {
        "PartyIdentification" => [
          { "ID" => [ { "_" => GENERAL_CONSUMER_TIN, "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => NA_VALUE, "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ {
          "CityName" => [ { "_" => "" } ],
          "PostalZone" => [ { "_" => "" } ],
          "CountrySubentityCode" => [ { "_" => "" } ],
          "AddressLine" => [
            { "Line" => [ { "_" => NA_VALUE } ] },
            { "Line" => [ { "_" => "" } ] },
            { "Line" => [ { "_" => "" } ] }
          ],
          "Country" => [ { "IdentificationCode" => [ { "_" => "", "listID" => COUNTRY_LIST_ID, "listAgencyID" => COUNTRY_LIST_AGENCY_ID } ] } ]
        } ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => GENERAL_CONSUMER_NAME } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => NA_VALUE } ],
          "ElectronicMail" => [ { "_" => NA_VALUE } ]
        } ]
      }
    end

    def invoice_lines
      @bookings.each_with_index.map do |booking, idx|
        # OTA stays are filed at net: the guest's gross includes commission
        # the hotel never receives.
        amount = booking.e_invoice_amount
        hotel_name = booking.hotel.name
        ref = booking.confirmation_token.to_s.upcase

        {
          "ID" => [ { "_" => (idx + 1).to_s } ],
          "InvoicedQuantity" => [ { "_" => 1, "unitCode" => UNIT_CODE_EACH } ],
          "LineExtensionAmount" => [ { "_" => amount.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ],
          "AllowanceCharge" => [ zero_allowance_charge ],
          "TaxTotal" => [ {
            "TaxAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
            "TaxSubtotal" => [ exempt_tax_subtotal(amount) ]
          } ],
          "Item" => [ {
            "CommodityClassification" => [ {
              "ItemClassificationCode" => [ { "_" => ACCOMMODATION_CLASS_CODE, "listID" => "CLASS" } ]
            } ],
            "Description" => [ { "_" => "#{hotel_name} - #{ref} - #{amount.to_f}" } ],
            "OriginCountry" => [ { "IdentificationCode" => [ { "_" => ORIGIN_COUNTRY_CODE } ] } ]
          } ],
          "Price" => [ { "PriceAmount" => [ { "_" => amount.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ] } ],
          "ItemPriceExtension" => [ { "Amount" => [ { "_" => amount.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ] } ]
        }
      end
    end

    def exempt_tax_subtotal(taxable_amount)
      {
        "TaxableAmount" => [ { "_" => taxable_amount.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ],
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxCategory" => [ {
          "ID" => [ { "_" => "E" } ],
          "TaxExemptionReason" => [ { "_" => "Not subject to tax at line level" } ],
          "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
        } ]
      }
    end

    def tax_total_block
      subtotal = total_subtotal
      {
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "TaxSubtotal" => [ exempt_tax_subtotal(subtotal) ]
      }
    end

    def monetary_total
      subtotal = total_subtotal
      {
        "LineExtensionAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ],
        "TaxExclusiveAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ],
        "TaxInclusiveAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ],
        "AllowanceTotalAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "ChargeTotalAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "PayableRoundingAmount" => [ { "_" => 0.0, "currencyID" => DEFAULT_CURRENCY } ],
        "PayableAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => DEFAULT_CURRENCY } ]
      }
    end

    def total_subtotal
      @bookings.sum(&:e_invoice_amount)
    end

    def country_identification_code(code)
      { "_" => code, "listID" => COUNTRY_LIST_ID, "listAgencyID" => COUNTRY_LIST_AGENCY_ID }
    end

    def zero_allowance_charge
      ZERO_ALLOWANCE_CHARGE.deep_dup.tap do |allowance|
        allowance["Amount"].first["currencyID"] = DEFAULT_CURRENCY
      end
    end

    def validate_required_data!
      raise ArgumentError, "Hotel is required" unless @hotel
      raise ArgumentError, "MyInvois credentials not configured" if @creds.blank?
      return unless @context&.intermediary?

      raise ArgumentError, "Hotel e-invoice setting is missing" unless @setting
    end


    def hotel_supplier_profile
      {
        tin: @setting.hotel_tin.to_s,
        brn: @setting.hotel_brn.to_s,
        name: @setting.supplier_name,
        msic_code: @setting.supplier_msic_code.to_s,
        business_description: @setting.supplier_business_description.to_s,
        phone: format_phone(@setting.supplier_contact_phone_value),
        email: @setting.supplier_contact_email_value.to_s,
        address_line1: @setting.supplier_address_line1_value.to_s.presence || NA_VALUE,
        city: @setting.supplier_city_value.to_s,
        postal_code: @setting.supplier_postal_code.to_s,
        state_code: @setting.supplier_state_code.to_s,
        country_code: @setting.supplier_country_code_value.to_s.presence || ORIGIN_COUNTRY_CODE
      }
    end
  end
end
