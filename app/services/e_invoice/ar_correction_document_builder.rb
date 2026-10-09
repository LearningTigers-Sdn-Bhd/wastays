# frozen_string_literal: true

module EInvoice
  # Uses the shared UBL envelope/signing, but never reads booking room totals or
  # guest identity: every monetary line and buyer comes from this exact invoice.
  class ArCorrectionDocumentBuilder < DocumentBuilder
    def initialize(correction:, submission:, original_submission:)
      @correction = correction
      @submission = submission
      @original_submission = original_submission
      @snapshot = (credit? ? correction.original_snapshot : correction.corrected_snapshot).deep_stringify_keys
      super(correction.booking_folio.booking,
        context: SubmissionContext.for_submission(original_submission), buyer_snapshot: original_submission.buyer_snapshot)
    end

    private

    def validate_required_data!
      raise ArgumentError, "Company buyer TIN and registration number are required." if @buyer["tin"].blank? || @buyer["government_id"].blank?
      raise ArgumentError, "The invoice snapshot has no monetary totals." if @snapshot["totals"].blank?
      raise ArgumentError, "Company buyer address is required." if @buyer["billing_address"].blank?
    end

    def credit? = @submission.document_type == "02"
    def internal_id = @submission.internal_id
    def currency = @snapshot.dig("folio", "currency")
    def buyer_identifier_scheme = "BRN"
    def buyer_identifier = { "_" => @buyer.fetch("government_id"), "schemeID" => "BRN" }
    def buyer_tin = @buyer.fetch("tin")
    def buyer_value(key, fallback = nil) = @buyer[key]
    def buyer_address_value(key, fallback = nil) = @buyer.dig("billing_address", key)
    def guest_country_code = @buyer.dig("billing_address", "country_code")
    def buyer_city = @buyer.dig("billing_address", "city")
    def buyer_state_code = @buyer.dig("billing_address", "state_code")
    def buyer_postal_code = @buyer.dig("billing_address", "postal_code").presence || "00000"

    def invoice_period
      { "StartDate" => [ { "_" => @snapshot.dig("booking", "check_in").to_date.iso8601 } ],
        "EndDate" => [ { "_" => @snapshot.dig("booking", "check_out").to_date.iso8601 } ],
        "Description" => [ { "_" => "Accommodation Period" } ] }
    end

    def build_payload
      body = {
        "ID" => [ { "_" => internal_id } ], "IssueDate" => [ { "_" => issue_date } ],
        "IssueTime" => [ { "_" => issue_time } ],
        "InvoiceTypeCode" => [ { "_" => @submission.document_type, "listVersionID" => document_version } ],
        "DocumentCurrencyCode" => [ { "_" => currency } ],
        "AccountingSupplierParty" => [ { "Party" => [ supplier_party ] } ],
        "AccountingCustomerParty" => [ { "Party" => [ buyer_party ] } ],
        "InvoiceLine" => invoice_lines, "TaxTotal" => [ tax_total_block ],
        "LegalMonetaryTotal" => [ monetary_total ]
      }
      payload = UBL_NAMESPACES.merge("Invoice" => [ body ])
      body["InvoiceTypeCode"].first["_"] = @submission.document_type
      if credit?
        body["BillingReference"] = [ {
          "InvoiceDocumentReference" => [ {
            "ID" => [ { "_" => @original_submission.internal_id } ],
            "UUID" => [ { "_" => @original_submission.uuid } ]
          } ]
        } ]
      end
      document_signer.apply(payload)
    end

    def supplier_profile
      profile = super
      frozen = @snapshot.fetch("hotel")
      profile.merge(name: frozen["name"], tin: @original_submission.supplier_tin.presence || frozen["tin"],
        address_line1: frozen["address"], city: frozen["city"])
    end

    def transaction_rows
      @snapshot.fetch("transactions").reject { |row| row["transaction_type"] == "payment" }
    end

    def tax_rows
      by_id = transaction_rows.index_by { |row| row["id"] }
      transaction_rows.select do |row|
        source = by_id[row["reversal_of_transaction_id"]] || row
        source["category"] == "tax" && source.dig("metadata", "tax_line", "type") != "service_charge"
      end
    end

    def tax_amount = tax_rows.sum { |row| row["amount"].to_d }
    def gross_amount = @snapshot.dig("totals", "charges").to_d + @snapshot.dig("totals", "adjustments").to_d
    def subtotal_amount = gross_amount - tax_amount

    def invoice_lines
      line = {
        "ID" => [ { "_" => "1" } ],
        "InvoicedQuantity" => [ { "_" => 1, "unitCode" => UNIT_CODE_EACH } ],
        "LineExtensionAmount" => money(subtotal_amount),
        "TaxTotal" => [ tax_total_block ],
        "Item" => [ {
          "CommodityClassification" => [ { "ItemClassificationCode" => [ { "_" => ACCOMMODATION_CLASS_CODE, "listID" => "CLASS" } ] } ],
          "Description" => [ { "_" => credit? ? "Cancellation of #{@original_submission.internal_id}" : "Corrected company folio charges" } ]
        } ],
        "Price" => [ { "PriceAmount" => money(subtotal_amount) } ],
        "ItemPriceExtension" => [ { "Amount" => money(subtotal_amount) } ]
      }
      [ line ]
    end

    def tax_total_block
      by_id = transaction_rows.index_by { |row| row["id"] }
      totals = tax_rows.group_by do |row|
        source = by_id[row["reversal_of_transaction_id"]] || row
        type = source.dig("metadata", "tax_line", "type").presence || source["description"]
        code = lhdn_tax_code(type)
        raise ArgumentError, "The captured tax type #{type} cannot be mapped to LHDN." if code == "OTH"
        code
      end.transform_values { |rows| rows.sum { |row| row["amount"].to_d } }
      subtotals = totals.filter_map do |code, amount|
        next if amount.zero?
        { "TaxableAmount" => money(subtotal_amount), "TaxAmount" => money(amount),
          "TaxCategory" => [ { "ID" => [ { "_" => code } ],
            "TaxScheme" => [ { "ID" => [ { "_" => "OTH", "schemeID" => "UN/ECE 5153", "schemeAgencyID" => "6" } ] } ] } ] }
      end
      { "TaxAmount" => money(tax_amount),
        "TaxSubtotal" => subtotals.presence || [ exempt_tax_subtotal(subtotal_amount) ] }
    end

    def monetary_total
      { "LineExtensionAmount" => money(subtotal_amount), "TaxExclusiveAmount" => money(subtotal_amount),
        "TaxInclusiveAmount" => money(gross_amount), "AllowanceTotalAmount" => money(0),
        "ChargeTotalAmount" => money(0), "PrepaidAmount" => money(@snapshot.dig("totals", "payments").to_d),
        "PayableRoundingAmount" => money(0), "PayableAmount" => money(@snapshot.dig("totals", "balance").to_d) }
    end

    def money(amount) = [ { "_" => amount.to_d.round(2).to_f, "currencyID" => currency } ]
  end
end
