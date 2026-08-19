# frozen_string_literal: true

require "digest"
require "base64"

module EInvoice
  class AdjustmentNoteBuilder
    include PhoneFormatter

    DEBIT_NOTE_TYPE_CODE     = "03"
    CREDIT_NOTE_TYPE_CODE    = "02"
    ACCOMMODATION_CLASS_CODE = "022"
    GENERAL_CONSUMER_TIN     = "EI00000000010"
    DEFAULT_CURRENCY         = "MYR"
    ORIGIN_COUNTRY_CODE      = "MYS"
    COUNTRY_LIST_ID          = "ISO3166-1"
    COUNTRY_LIST_AGENCY_ID   = "6"
    UNIT_CODE_EACH           = "C62"
    ZERO_ALLOWANCE_CHARGE    = {
      "ChargeIndicator" => [ { "_" => false } ],
      "Amount" => [ { "_" => 0, "currencyID" => DEFAULT_CURRENCY } ]
    }.freeze

    UBL_NAMESPACES = {
      "_D" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
      "_A" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
      "_B" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
    }.freeze

    def initialize(booking:, original_submission:, adjustment_amount:, document_type:)
      @booking = booking
      @hotel = booking.hotel
      @original_submission = original_submission
      @adjustment_amount = adjustment_amount.to_d.abs
      @document_type = document_type
      @creds = Rails.application.credentials.myinvois.to_h
      @context = EInvoice::SubmissionContext.for(booking)
      @setting = booking.hotel&.e_invoice_setting
      validate_required_data!
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

    def debit_note?
      @document_type == DEBIT_NOTE_TYPE_CODE
    end

    def credit_note?
      @document_type == CREDIT_NOTE_TYPE_CODE
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
        "InvoiceTypeCode" => [ { "_" => @document_type, "listVersionID" => document_version } ],
        "DocumentCurrencyCode" => [ { "_" => currency } ],
        "TaxCurrencyCode" => [ { "_" => currency } ],
        "BillingReference" => [ {
          "AdditionalDocumentReference" => [ {
            "ID" => [ { "_" => @original_submission.internal_id.to_s } ]
          } ]
        } ],
        "AccountingSupplierParty" => [ { "Party" => [ supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ buyer_party ] } ],
        "InvoiceLine" => [ adjustment_line ],
        "TaxTotal" => [ tax_total_block ],
        "LegalMonetaryTotal" => [ monetary_total ]
      }
    end

    def internal_id
      suffix = debit_note? ? "DN" : "CN"
      "#{@original_submission.internal_id}-#{suffix}"
    end

    def issue_date
      Time.current.to_date.iso8601
    end

    def issue_time
      Time.current.utc.strftime("%H:%M:%SZ")
    end

    def currency
      @booking.currency.presence || @hotel.default_currency.presence || DEFAULT_CURRENCY
    end

    def supplier_party
      supplier = supplier_profile
      {
        "IndustryClassificationCode" => [ { "_" => supplier[:msic_code], "name" => supplier[:business_description] } ],
        "PartyIdentification" => [
          { "ID" => [ { "_" => supplier[:tin], "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => supplier[:brn], "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ supplier_address(supplier) ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => supplier[:name] } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => supplier[:phone] } ],
          "ElectronicMail" => [ { "_" => supplier[:email] } ]
        } ]
      }
    end

    # The hotel is the supplier on every guest e-invoice. WAStays is under the
    # RM1m threshold and files nothing as itself; self-billed payout documents
    # are built elsewhere, by PayoutSelfBilledDocumentBuilder.
    def supplier_profile
      hotel_supplier_profile
    end


    def hotel_supplier_profile
      raise ArgumentError, "Hotel e-invoice setting is missing" unless @setting
      {
        tin: @setting.hotel_tin.to_s,
        brn: @setting.hotel_brn.to_s,
        name: @setting.supplier_name,
        msic_code: @setting.supplier_msic_code.to_s,
        business_description: @setting.supplier_business_description.to_s,
        phone: format_phone(@setting.supplier_contact_phone_value),
        email: @setting.supplier_contact_email_value.to_s,
        address_line1: @setting.supplier_address_line1_value.to_s,
        address_line2: @setting.supplier_address_line2_value.to_s,
        city: @setting.supplier_city_value.to_s,
        postal_code: @setting.supplier_postal_code.to_s,
        state_code: @setting.supplier_state_code.to_s,
        country_code: @setting.supplier_country_code_value.to_s
      }
    end

    def supplier_address(supplier)
      {
        "CityName" => [ { "_" => supplier[:city] } ],
        "PostalZone" => [ { "_" => supplier[:postal_code] } ],
        "CountrySubentityCode" => [ { "_" => supplier[:state_code] } ],
        "AddressLine" => [
          { "Line" => [ { "_" => supplier[:address_line1] } ] },
          { "Line" => [ { "_" => supplier[:address_line2].to_s } ] },
          { "Line" => [ { "_" => "" } ] }
        ],
        "Country" => [ { "IdentificationCode" => [ country_identification_code(supplier[:country_code]) ] } ]
      }
    end

    def buyer_party
      {
        "PartyIdentification" => [
          { "ID" => [ { "_" => buyer_tin, "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => "NA", "schemeID" => "BRN" } ] }
        ],
        "PostalAddress" => [ {
          "CityName" => [ { "_" => buyer_city } ],
          "PostalZone" => [ { "_" => buyer_postal_code } ],
          "CountrySubentityCode" => [ { "_" => buyer_state_code } ],
          "AddressLine" => [
            { "Line" => [ { "_" => "NA" } ] },
            { "Line" => [ { "_" => "" } ] },
            { "Line" => [ { "_" => "" } ] }
          ],
          "Country" => [ { "IdentificationCode" => [ country_identification_code(ORIGIN_COUNTRY_CODE) ] } ]
        } ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => @booking.guest_name.to_s } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => format_phone(@booking.guest_phone) } ],
          "ElectronicMail" => [ { "_" => @booking.guest_email.to_s } ]
        } ]
      }
    end

    def adjustment_line
      description = debit_note? ? "Additional charges adjustment" : "Refund/credit adjustment"
      {
        "ID" => [ { "_" => "1" } ],
        "InvoicedQuantity" => [ { "_" => 1, "unitCode" => UNIT_CODE_EACH } ],
        "LineExtensionAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ],
        "AllowanceCharge" => [ zero_allowance_charge ],
        "TaxTotal" => [ {
          "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
          "TaxSubtotal" => [ {
            "TaxableAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ],
            "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
            "TaxCategory" => [ {
              "ID" => [ { "_" => "E" } ],
              "TaxExemptionReason" => [ { "_" => "Not subject to tax at line level" } ],
              "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
            } ]
          } ]
        } ],
        "Item" => [ {
          "CommodityClassification" => [ {
            "ItemClassificationCode" => [ { "_" => ACCOMMODATION_CLASS_CODE, "listID" => "CLASS" } ]
          } ],
          "Description" => [ { "_" => description } ],
          "OriginCountry" => [ { "IdentificationCode" => [ { "_" => ORIGIN_COUNTRY_CODE } ] } ]
        } ],
        "Price" => [ { "PriceAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ] } ],
        "ItemPriceExtension" => [ { "Amount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ] } ]
      }
    end

    def tax_total_block
      {
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "TaxSubtotal" => [ {
          "TaxableAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ],
          "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
          "TaxCategory" => [ {
            "ID" => [ { "_" => "E" } ],
            "TaxExemptionReason" => [ { "_" => "Not subject to tax at line level" } ],
            "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
          } ]
        } ]
      }
    end

    def monetary_total
      {
        "LineExtensionAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ],
        "TaxExclusiveAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ],
        "TaxInclusiveAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ],
        "AllowanceTotalAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "ChargeTotalAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "PayableRoundingAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "PayableAmount" => [ { "_" => @adjustment_amount.to_f.round(2), "currencyID" => currency } ]
      }
    end

    def country_identification_code(code)
      { "_" => code, "listID" => COUNTRY_LIST_ID, "listAgencyID" => COUNTRY_LIST_AGENCY_ID }
    end

    def buyer_city
      @booking.guest_city.to_s.presence || raise(ArgumentError, "Booking guest city is required")
    end

    def buyer_state_code
      EInvoice::MalaysiaStates.resolve(
        state_code: @booking.guest_state_code,
        city: @booking.guest_city,
        country_code: guest_country_code
      ) || raise(ArgumentError, "Booking needs a buyer state before it can be filed with LHDN")
    end

    # An adjustment note must carry the same buyer identity as the invoice it
    # references, or LHDN cannot match the two.
    def buyer_tin
      @booking.buyer_tin_for_e_invoice.presence || GENERAL_CONSUMER_TIN
    end

    def buyer_postal_code
      @booking.guest_postal_code.to_s.gsub(/\D/, "").presence || "00000"
    end

    def guest_country_code
      country = @booking.guest_country.presence || @hotel.country
      return ORIGIN_COUNTRY_CODE if country.blank?

      if defined?(ISO3166::Country)
        found = ISO3166::Country.find_country_by_any_name(country)
        found ? found.alpha3 : ORIGIN_COUNTRY_CODE
      else
        ORIGIN_COUNTRY_CODE
      end
    end

    def zero_allowance_charge
      ZERO_ALLOWANCE_CHARGE.deep_dup.tap do |allowance|
        allowance["Amount"].first["currencyID"] = currency
      end
    end

    def validate_required_data!
      raise ArgumentError, "Booking must have an associated hotel" unless @hotel
      raise ArgumentError, "Original submission is required" unless @original_submission
      raise ArgumentError, "Original submission must have a UUID" unless @original_submission.uuid.present?
      raise ArgumentError, "Adjustment amount must be positive" unless @adjustment_amount.positive?
      raise ArgumentError, "Document type must be 02 (Credit Note) or 03 (Debit Note)" unless %w[02 03].include?(@document_type)
    end
  end
end
