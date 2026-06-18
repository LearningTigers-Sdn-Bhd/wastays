# frozen_string_literal: true

require "digest"
require "base64"

module EInvoice
  # Builds a LHDN MyInvois UBL 2.1 JSON document (Invoice type 01) for a WAStays booking.
  #
  # WAStays (Jesselton Pixel Sdn Bhd) is ALWAYS the Supplier on this invoice.
  # The Guest is the Buyer. For B2C guests without a TIN, LHDN's general consumer
  # TIN "EI00000000010" is used as the default.
  #
  # Supplier details are read from Rails credentials (myinvois.*).
  # Line items come from booking_rooms; taxes from booking.tax_lines.
  #
  # Usage:
  #   result = EInvoice::DocumentBuilder.new(booking).build
  #   result[:document]      # Base64-encoded JSON string
  #   result[:documentHash]  # SHA-256 hex digest
  #   result[:codeNumber]    # Internal invoice number
  class DocumentBuilder
    DOCUMENT_VERSION         = "1.0"
    INVOICE_TYPE_CODE        = "01"      # Normal invoice
    ACCOMMODATION_CLASS_CODE = "022"     # LHDN commodity: accommodation
    WASTAYS_MSIC_CODE        = "63120"   # MSIC: Web portals / online booking platform
    GENERAL_CONSUMER_TIN     = "EI00000000010"  # LHDN default TIN for B2C guests

    UBL_NAMESPACES = {
      "_D" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
      "_A" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
      "_B" => "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
    }.freeze

    def initialize(booking)
      @booking = booking
      @hotel   = booking.hotel
      @folio   = booking.booking_folio
      @rooms   = booking.booking_rooms.includes(:room_type)
      @creds   = Rails.application.credentials.myinvois.to_h
    end

    # Returns a hash ready to be included in the documents array for submit_documents:
    #   format:       "JSON"
    #   document:     Base64-encoded UBL JSON string
    #   documentHash: SHA-256 hex digest of that JSON string
    #   codeNumber:   Internal invoice reference number
    def build
      payload_json = build_payload.to_json
      {
        format:       "JSON",
        document:     Base64.strict_encode64(payload_json),
        documentHash: Digest::SHA256.hexdigest(payload_json),
        codeNumber:   internal_id
      }
    end

    private

    # ─────────────────────────────────────────────
    # UBL Payload
    # ─────────────────────────────────────────────

    def build_payload
      UBL_NAMESPACES.merge("Invoice" => [ invoice_body ])
    end

    def invoice_body
      {
        "ID"                      => [ { "_" => internal_id } ],
        "IssueDate"               => [ { "_" => issue_date } ],
        "IssueTime"               => [ { "_" => issue_time } ],
        "InvoiceTypeCode"         => [ { "_" => INVOICE_TYPE_CODE, "listVersionID" => DOCUMENT_VERSION } ],
        "DocumentCurrencyCode"    => [ { "_" => currency } ],
        "TaxCurrencyCode"         => [ { "_" => currency } ],
        "InvoicePeriod"           => [ invoice_period ],
        "AccountingSupplierParty" => [ { "Party" => [ supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ buyer_party ] } ],
        "InvoiceLine"             => invoice_lines,
        "TaxTotal"                => [ tax_total_block ],
        "LegalMonetaryTotal"      => [ monetary_total ]
      }
    end

    # ─────────────────────────────────────────────
    # Header
    # ─────────────────────────────────────────────

    def internal_id
      @booking.formatted_invoice_number.presence ||
        @booking.formatted_folio_number.presence ||
        @booking.confirmation_token
    end

    def issue_date
      issued_at = @booking.checked_out_at || @booking.check_out
      issued_at.to_date.iso8601
    end

    def issue_time
      issued_at = @booking.checked_out_at || @booking.check_out
      issued_at.utc.strftime("%H:%M:%SZ")
    end

    def currency
      @booking.currency.presence || @hotel.default_currency.presence || "MYR"
    end

    def invoice_period
      {
        "StartDate"   => [ { "_" => @booking.check_in.to_date.iso8601 } ],
        "EndDate"     => [ { "_" => @booking.check_out.to_date.iso8601 } ],
        "Description" => [ { "_" => "Accommodation Period" } ]
      }
    end

    # ─────────────────────────────────────────────
    # Supplier — WAStays (Jesselton Pixel Sdn Bhd)
    # All values sourced from Rails credentials.myinvois.*
    # ─────────────────────────────────────────────

    def supplier_party
      {
        "IndustryClassificationCode" => [ { "_" => WASTAYS_MSIC_CODE, "name" => "Web portals — Online hotel booking platform" } ],
        "PartyIdentification"        => [
          { "ID" => [ { "_" => wastays_tin,  "schemeID" => "TIN" } ] },
          { "ID" => [ { "_" => wastays_brn,  "schemeID" => "BRN" } ] }
        ],
        "PostalAddress"              => [ wastays_address ],
        "PartyLegalEntity"           => [ { "CompanyID" => [ { "_" => wastays_brn } ] } ],
        "Contact"                    => [ {
          "Telephone"      => [ { "_" => @creds[:phone].to_s.presence || "+60111234567" } ],
          "ElectronicMail" => [ { "_" => @creds[:email].to_s.presence || "finance@wastays.com" } ]
        } ],
        "PartyName"                  => [ { "Name" => [ { "_" => wastays_name } ] } ]
      }
    end

    def wastays_address
      {
        "CityName"             => [ { "_" => @creds[:city].to_s.presence || "Kota Kinabalu" } ],
        "PostalZone"           => [ { "_" => @creds[:postal_code].to_s.presence || "88000" } ],
        "CountrySubentityCode" => [ { "_" => @creds[:state_code].to_s.presence || "12" } ],
        "AddressLine"          => [
          { "Line" => [ { "_" => @creds[:address].to_s.presence || "NA" } ] },
          { "Line" => [ { "_" => "" } ] },
          { "Line" => [ { "_" => "" } ] }
        ],
        "Country"              => [ { "IdentificationCode" => [ { "_" => "MYS" } ] } ]
      }
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

    # ─────────────────────────────────────────────
    # Buyer — Guest (B2C, no TIN)
    # ─────────────────────────────────────────────

    def buyer_party
      {
        "PartyIdentification" => [
          { "ID" => [ { "_" => GENERAL_CONSUMER_TIN, "schemeID" => "TIN" } ] }
        ],
        "PostalAddress"       => [ buyer_address ],
        "PartyLegalEntity"    => [ { "CompanyID" => [ { "_" => GENERAL_CONSUMER_TIN } ] } ],
        "Contact"             => [ {
          "Telephone"      => [ { "_" => format_phone(@booking.guest_phone) } ],
          "ElectronicMail" => [ { "_" => @booking.guest_email.to_s } ]
        } ],
        "PartyName"           => [ { "Name" => [ { "_" => @booking.guest_name.to_s } ] } ]
      }
    end

    def buyer_address
      {
        "CityName"             => [ { "_" => "" } ],
        "PostalZone"           => [ { "_" => "00000" } ],
        "CountrySubentityCode" => [ { "_" => "00" } ],
        "AddressLine"          => [
          { "Line" => [ { "_" => "NA" } ] },
          { "Line" => [ { "_" => "" } ] },
          { "Line" => [ { "_" => "" } ] }
        ],
        "Country"              => [ { "IdentificationCode" => [ { "_" => guest_country_code } ] } ]
      }
    end

    # ─────────────────────────────────────────────
    # Line Items — one per BookingRoom
    # ─────────────────────────────────────────────

    def invoice_lines
      nights = (@booking.check_out.to_date - @booking.check_in.to_date).to_i

      @rooms.each_with_index.map do |room, idx|
        subtotal   = room.subtotal.to_d
        room_name  = room.room_type_snapshot["name"].presence || room.room_type&.name || "Accommodation"
        desc       = "#{room_name} × #{room.quantity} room(s) × #{nights} night(s)"
        qty        = room.quantity.to_i
        unit_price = qty > 0 ? (subtotal / qty).to_f.round(4) : subtotal.to_f.round(2)

        {
          "ID"                  => [ { "_" => (idx + 1).to_s } ],
          "InvoiceQuantity"     => [ { "_" => qty, "unitCode" => "NIT" } ],
          "LineExtensionAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ],
          "AllowanceCharge"     => [ {
            "ChargeIndicator" => [ { "_" => false } ],
            "Amount"          => [ { "_" => 0, "currencyID" => currency } ]
          } ],
          "TaxTotal"            => [ {
            "TaxAmount"   => [ { "_" => 0.0, "currencyID" => currency } ],
            "TaxSubtotal" => [ exempt_tax_subtotal(subtotal) ]
          } ],
          "Item"                => [ {
            "CommodityClassification" => [ {
              "ItemClassificationCode" => [ { "_" => ACCOMMODATION_CLASS_CODE, "listID" => "CLASS" } ]
            } ],
            "Description"    => [ { "_" => desc } ],
            "OriginCountry"  => [ { "IdentificationCode" => [ { "_" => "MYS" } ] } ]
          } ],
          "Price"              => [ { "PriceAmount" => [ { "_" => unit_price, "currencyID" => currency } ] } ],
          "ItemPriceExtension" => [ { "Amount"      => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ] } ]
        }
      end
    end

    def exempt_tax_subtotal(taxable_amount)
      {
        "TaxableAmount" => [ { "_" => taxable_amount.to_f.round(2), "currencyID" => currency } ],
        "TaxAmount"     => [ { "_" => 0.0, "currencyID" => currency } ],
        "TaxCategory"   => [ {
          "ID"                 => [ { "_" => "E" } ],
          "TaxExemptionReason" => [ { "_" => "Not subject to tax at line level" } ],
          "TaxScheme"          => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
        } ]
      }
    end

    # ─────────────────────────────────────────────
    # Tax Total — from booking.tax_lines
    # ─────────────────────────────────────────────

    def tax_total_block
      tax_lines = Array(@booking.tax_lines)
      tax_amount = tax_lines.sum { |t| t["amount"].to_d }
      subtotal   = subtotal_amount

      {
        "TaxAmount"   => [ { "_" => tax_amount.to_f.round(2), "currencyID" => currency } ],
        "TaxSubtotal" => tax_lines.any? ? tax_subtotal_rows(tax_lines, subtotal) : [ exempt_tax_subtotal(subtotal) ]
      }
    end

    def tax_subtotal_rows(tax_lines, subtotal)
      tax_lines.map do |tax|
        amount   = tax["amount"].to_d
        type_code = lhdn_tax_code(tax["type"] || tax["name"])
        {
          "TaxableAmount" => [ { "_" => subtotal.to_f.round(2), "currencyID" => currency } ],
          "TaxAmount"     => [ { "_" => amount.to_f.round(2), "currencyID" => currency } ],
          "TaxCategory"   => [ {
            "ID"                 => [ { "_" => type_code } ],
            "TaxExemptionReason" => [ { "_" => "" } ],
            "TaxScheme"          => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ]
          } ]
        }
      end
    end

    # ─────────────────────────────────────────────
    # Monetary Totals
    # ─────────────────────────────────────────────

    def monetary_total
      sub   = subtotal_amount
      total = @booking.total_amount.to_d
      {
        "LineExtensionAmount"   => [ { "_" => sub.to_f.round(2),   "currencyID" => currency } ],
        "TaxExclusiveAmount"    => [ { "_" => sub.to_f.round(2),   "currencyID" => currency } ],
        "TaxInclusiveAmount"    => [ { "_" => total.to_f.round(2), "currencyID" => currency } ],
        "AllowanceTotalAmount"  => [ { "_" => 0.0,                 "currencyID" => currency } ],
        "ChargeTotalAmount"     => [ { "_" => 0.0,                 "currencyID" => currency } ],
        "PayableRoundingAmount" => [ { "_" => 0.0,                 "currencyID" => currency } ],
        "PayableAmount"         => [ { "_" => total.to_f.round(2), "currencyID" => currency } ]
      }
    end

    # ─────────────────────────────────────────────
    # Helpers
    # ─────────────────────────────────────────────

    def subtotal_amount
      @rooms.sum { |r| r.subtotal.to_d }
    end

    def lhdn_tax_code(type_hint)
      hint = type_hint.to_s.downcase
      return "02" if hint.include?("service") || hint.include?("sst")
      return "03" if hint.include?("tourism") || hint.include?("ttx")
      "OTH"
    end

    def guest_country_code
      country = @booking.guest_country.presence || @hotel.country
      return "MYS" if country.blank?
      if defined?(ISO3166::Country)
        found = ISO3166::Country.find_country_by_any_name(country)
        found ? found.alpha3 : "MYS"
      else
        "MYS"
      end
    end

    def format_phone(phone)
      return "+60123456789" if phone.blank?
      phone.to_s.strip.then { |p| p.start_with?("+") ? p : "+#{p.gsub(/\D/, '')}" }
    end
  end
end
