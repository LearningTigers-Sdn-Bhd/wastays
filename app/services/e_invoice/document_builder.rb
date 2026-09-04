# frozen_string_literal: true

require "digest"
require "base64"

module EInvoice
  class DocumentBuilder
    include PhoneFormatter

    INVOICE_TYPE_CODE        = "01"
    ACCOMMODATION_CLASS_CODE = "022"
    WASTAYS_MSIC_CODE        = "63120"
    # LHDN's general-public placeholder (010) is confirmed, by LHDN's own
    # validator (ERR228 "General TIN (010) is not allowed for NON-consolidated
    # e-invoice"), to be usable only on consolidated e-invoices. This builder
    # never builds a consolidated document, so it must never fall back to it.
    FOREIGN_BUYER_TIN        = "EI00000000020"
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

    def initialize(booking, context: EInvoice::SubmissionContext.for(booking), buyer_snapshot: nil)
      @booking = booking
      @hotel = booking.hotel
      @rooms = booking.booking_rooms.includes(:room_type)
      @context = context
      @setting = booking.hotel&.e_invoice_setting
      @buyer = buyer_snapshot.to_h.stringify_keys.presence
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
        "AccountingSupplierParty" => [ { "Party" => [ supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ buyer_party ] } ],
        "InvoiceLine" => invoice_lines,
        "TaxTotal" => [ tax_total_block ],
        "LegalMonetaryTotal" => [ monetary_total ]
      }
    end

    def internal_id
      @booking.send(:formatted_invoice_number).presence ||
        @booking.send(:formatted_folio_number).presence ||
        @booking.confirmation_token
    end

    # LHDN validates that a document is issued now, not backdated. The payment
    # date is the taxable event and still governs which month a guest may
    # request in, but it is not when the document was issued: a guest asking on
    # the 20th for a stay paid on the 5th would otherwise produce a document
    # two weeks old, which LHDN rejects.
    def issue_date
      Time.current.utc.to_date.iso8601
    end

    def issue_time
      Time.current.utc.strftime("%H:%M:%SZ")
    end

    def currency
      @booking.currency.presence || @hotel.default_currency.presence || DEFAULT_CURRENCY
    end

    def invoice_period
      {
        "StartDate" => [ { "_" => @booking.check_in.to_date.iso8601 } ],
        "EndDate" => [ { "_" => @booking.check_out.to_date.iso8601 } ],
        "Description" => [ { "_" => "Accommodation Period" } ]
      }
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
      }.tap do |party|
        if supplier[:sst_registration_number].present?
          party["PartyIdentification"] << { "ID" => [ { "_" => supplier[:sst_registration_number], "schemeID" => "SST" } ] }
        end
      end
    end

    # The hotel is the supplier on every guest e-invoice. WAStays is under the
    # RM1m threshold and files nothing as itself; self-billed payout documents
    # are built elsewhere, by PayoutSelfBilledDocumentBuilder.
    def supplier_profile
      hotel_supplier_profile
    end


    def hotel_supplier_profile
      raise ArgumentError, "Hotel e-invoice setting is missing." unless @setting

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
        country_code: @setting.supplier_country_code_value.to_s,
        sst_registration_number: @setting.supplier_sst_registration_number.to_s.presence
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
          { "ID" => [ buyer_identifier ] }
        ],
        "PostalAddress" => [ buyer_address ],
        "PartyLegalEntity" => [ { "RegistrationName" => [ { "_" => buyer_value("name", @booking.guest_name).to_s } ] } ],
        "Contact" => [ {
          "Telephone" => [ { "_" => format_phone(buyer_value("contact_phone", @booking.guest_phone)) } ],
          "ElectronicMail" => [ { "_" => buyer_value("contact_email", @booking.guest_email).to_s } ]
        } ]
      }
    end

    def buyer_address
      {
        "CityName" => [ { "_" => buyer_city } ],
        "PostalZone" => [ { "_" => buyer_postal_code } ],
        "CountrySubentityCode" => [ { "_" => buyer_state_code } ],
        "AddressLine" => [
          { "Line" => [ { "_" => buyer_address_value("address_line1", @booking.guest_home_address).presence || "NA" } ] },
          { "Line" => [ { "_" => buyer_address_value("address_line2").to_s } ] },
          { "Line" => [ { "_" => "" } ] }
        ],
        "Country" => [ { "IdentificationCode" => [ country_identification_code(guest_country_code) ] } ]
      }
    end

    def invoice_lines
      nights = (@booking.check_out.to_date - @booking.check_in.to_date).to_i

      @rooms.each_with_index.map do |room, idx|
        subtotal = room.subtotal.to_d
        room_name = room.room_type_snapshot["name"].presence || room.room_type&.name || "Accommodation"
        # booking_rooms.quantity was dropped when the schema moved to one room
        # per booking_room row, so each line is always a single room.
        qty = 1
        desc = "#{room_name} x #{qty} room(s) x #{nights} night(s)"
        unit_price = subtotal.to_f.round(4)

        {
          "ID" => [ { "_" => (idx + 1).to_s } ],
          "InvoicedQuantity" => [ { "_" => qty, "unitCode" => UNIT_CODE_EACH } ],
          "LineExtensionAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ],
          "AllowanceCharge" => [ zero_allowance_charge ],
          "TaxTotal" => [ {
            "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
            "TaxSubtotal" => [ exempt_tax_subtotal(subtotal) ]
          } ],
          "Item" => [ {
            "CommodityClassification" => [ {
              "ItemClassificationCode" => [ { "_" => ACCOMMODATION_CLASS_CODE, "listID" => "CLASS" } ]
            } ],
            "Description" => [ { "_" => desc } ],
            "OriginCountry" => [ { "IdentificationCode" => [ { "_" => ORIGIN_COUNTRY_CODE } ] } ]
          } ],
          "Price" => [ { "PriceAmount" => [ { "_" => unit_price, "currencyID" => currency } ] } ],
          "ItemPriceExtension" => [ { "Amount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ] } ]
        }
      end
    end

    def exempt_tax_subtotal(taxable_amount)
      {
        "TaxableAmount" => [ { "_" => taxable_amount.to_f.round(2), "currencyID" => currency } ],
        "TaxAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "TaxCategory" => [ {
          "ID" => [ { "_" => "E" } ],
          "TaxExemptionReason" => [ { "_" => "Not subject to tax at line level" } ],
          "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
        } ]
      }
    end

    def tax_total_block
      tax_lines = Array(@booking.tax_lines)
      tax_amount = tax_lines.sum { |tax| tax["amount"].to_d }
      subtotal = subtotal_amount

      {
        "TaxAmount" => [ { "_" => tax_amount.to_f.round(2), "currencyID" => currency } ],
        "TaxSubtotal" => tax_lines.any? ? tax_subtotal_rows(tax_lines, subtotal) : [ exempt_tax_subtotal(subtotal) ]
      }
    end

    def tax_subtotal_rows(tax_lines, subtotal)
      tax_lines.map do |tax|
        amount = tax["amount"].to_d
        type_code = lhdn_tax_code(tax["type"] || tax["name"])
        {
          "TaxableAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ],
          "TaxAmount" => [ { "_" => amount.to_f.round(2), "currencyID" => currency } ],
          "TaxCategory" => [ {
            "ID" => [ { "_" => type_code } ],
            "TaxExemptionReason" => [ { "_" => "" } ],
            "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
          } ]
        }
      end
    end

    def monetary_total
      subtotal = subtotal_amount
      total = @booking.total_amount.to_d

      {
        "LineExtensionAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ],
        "TaxExclusiveAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ],
        "TaxInclusiveAmount" => [ { "_" => total.to_f.round(2), "currencyID" => currency } ],
        "AllowanceTotalAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "ChargeTotalAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "PayableRoundingAmount" => [ { "_" => 0.0, "currencyID" => currency } ],
        "PayableAmount" => [ { "_" => total.to_f.round(2), "currencyID" => currency } ]
      }
    end

    def subtotal_amount
      @rooms.sum { |room| room.subtotal.to_d }
    end

    def lhdn_tax_code(type_hint)
      hint = type_hint.to_s.downcase
      return "02" if hint.include?("service") || hint.include?("sst")
      return "03" if hint.include?("tourism") || hint.include?("ttx")

      "OTH"
    end

    def guest_country_code
      return buyer_address_value("country_code") if buyer_address_value("country_code").present?

      country = @booking.guest_address_country.presence || @booking.guest_country.presence || @hotel.country
      return "MYS" if country.blank?

      if defined?(ISO3166::Country)
        found = ISO3166::Country.find_country_by_any_name(country)
        found ? found.alpha3 : "MYS"
      else
        "MYS"
      end
    end

    def buyer_identifier
      value = buyer_value("government_id", @booking.guest_government_id).to_s.gsub(/[^A-Za-z0-9]/, "").presence || "NA"
      { "_" => value, "schemeID" => buyer_identifier_scheme }
    end

    def buyer_identifier_scheme
      case buyer_value("document_type", @booking.guest_document_type).to_s
      when "ic" then "NRIC"
      when "passport" then "PASSPORT"
      else "BRN"
      end
    end

    def buyer_city
      buyer_address_value("city", @booking.guest_city).to_s.presence || raise(ArgumentError, "Booking guest city is required")
    end

    def buyer_state_code
      EInvoice::MalaysiaStates.resolve(
        state_code: buyer_address_value("state_code", @booking.guest_state_code),
        city: buyer_city,
        country_code: guest_country_code
      ) || raise(ArgumentError, "Booking needs a buyer state before it can be filed with LHDN")
    end

    # A buyer who supplies their own TIN can claim the invoice. A foreign
    # guest without one is filed under LHDN's foreign-buyer placeholder. A
    # local guest without one has no valid placeholder at all - the request
    # should already have been blocked upstream by
    # Booking#e_invoice_buyer_details_missing, so reaching this case means
    # something let a booking through it shouldn't have.
    def buyer_tin
      tin = buyer_value("tin", @booking.buyer_tin_for_e_invoice).presence
      return tin if tin
      return FOREIGN_BUYER_TIN if foreign_buyer?

      raise ArgumentError, "This guest has no tax number on file. LHDN's general public TIN cannot be used on an individual (non-consolidated) e-invoice."
    end

    def buyer_postal_code
      buyer_address_value("postal_code", @booking.guest_postal_code).to_s.gsub(/\D/, "").presence || "00000"
    end

    def buyer_value(key, fallback = nil)
      @buyer&.fetch(key, nil).presence || fallback
    end

    def buyer_address_value(key, fallback = nil)
      @buyer&.dig("billing_address", key).presence || fallback
    end

    def foreign_buyer?
      nationality = buyer_value("nationality", @booking.guest_country).presence || @hotel.country
      ISO3166::Country.find_country_by_any_name(nationality)&.alpha3 != "MYS"
    end

    def country_identification_code(code)
      {
        "_" => code,
        "listID" => COUNTRY_LIST_ID,
        "listAgencyID" => COUNTRY_LIST_AGENCY_ID
      }
    end

    def format_phone(phone)
      return "+60123456789" if phone.blank?

      phone.to_s.strip.then { |value| value.start_with?("+") ? value : "+#{value.gsub(/\D/, '')}" }
    end

    def validate_required_data!
      raise ArgumentError, "Booking must have an associated hotel" unless @hotel
      raise ArgumentError, "Booking has no rooms" if @rooms.blank?
    end

    def zero_allowance_charge
      ZERO_ALLOWANCE_CHARGE.deep_dup.tap do |allowance|
        allowance["Amount"].first["currencyID"] = currency
      end
    end
  end
end
