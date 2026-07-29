# frozen_string_literal: true

require "set"

module Reports
  module Bookings
    class GenerateFolioRecords
      UnavailableError = Class.new(StandardError)

      TransactionRow = Struct.new(
        :date,
        :code,
        :description,
        :secondary_description,
        :quantity,
        :net,
        :charges,
        :gross,
        :kind,
        keyword_init: true
      )

      SummaryRow = Struct.new(:label, :amount, :credit, :emphasis, keyword_init: true)
      SnapshotCode = Data.define(:code, :name)
      SnapshotUser = Data.define(:name)

      class SnapshotTransaction
        attr_reader :id, :transaction_type, :category, :description, :amount,
          :currency, :posting_date, :created_at, :metadata,
          :reversal_of_transaction_id, :voided_by_transaction_id,
          :transaction_code, :user

        def initialize(attributes)
          attributes = attributes.to_h.stringify_keys
          @id = attributes["id"]
          @transaction_type = attributes["transaction_type"]
          @category = attributes["category"]
          @description = attributes["description"]
          @amount = attributes["amount"].to_d
          @currency = attributes["currency"]
          @posting_date = parse_date(attributes["posting_date"])
          @created_at = parse_time(attributes["created_at"])
          @metadata = attributes["metadata"].to_h
          @reversal_of_transaction_id = attributes["reversal_of_transaction_id"]
          @voided_by_transaction_id = attributes["voided_by_transaction_id"]
          @transaction_code = SnapshotCode.new(attributes["code"], attributes["code_name"]) if attributes["code"].present?
          @user = SnapshotUser.new(attributes["user_name"]) if attributes["user_name"].present?
        end

        def charge?
          transaction_type == "charge"
        end

        def payment?
          transaction_type == "payment"
        end

        def adjustment?
          transaction_type == "adjustment"
        end

        private

        def parse_date(value)
          Date.iso8601(value.to_s) if value.present?
        end

        def parse_time(value)
          Time.zone.parse(value.to_s) if value.present?
        end
      end

      FALLBACK_CODES = {
        "accommodation" => [ "RM-ACC", "Room / Accommodation" ],
        "tax" => [ "TAX", "Tax / Charge" ],
        "fb" => [ "FB", "Food & Beverage" ],
        "parking" => [ "PARK", "Parking" ],
        "no_show_charge" => [ "NO-SHOW", "No-Show Charge" ],
        "cancellation_charge" => [ "CANCEL", "Cancellation Charge" ],
        "late_checkout_charge" => [ "LATE", "Late Checkout Charge" ],
        "early_departure_charge" => [ "EARLY", "Early Departure Charge" ],
        "other" => [ "OTHER", "Other Charge" ],
        "adjustment" => [ "ADJ", "Adjustment" ],
        "correction" => [ "CORR", "Correction" ],
        "discount" => [ "DISC", "Discount" ],
        "write_off" => [ "W/O", "Write-Off" ],
        "gateway_payment" => [ "PAY-GW", "Payment / Settlement" ],
        "booking_payment" => [ "PAY-BKG", "Payment / Settlement" ],
        "cash" => [ "PAY-CASH", "Cash Payment" ],
        "refund" => [ "REFUND", "Refund" ]
      }.freeze

      PAYMENT_SOURCE_LABELS = {
        "cash" => "Cash",
        "bank" => "Bank Transfer",
        "card" => "Card Terminal",
        "gateway" => "Gateway Manual Recovery",
        "ota" => "OTA Collected"
      }.freeze

      PAYMENT_REFERENCE_KEYS = [
        [ "receipt_reference", "Receipt" ],
        [ "bank_reference", "Bank Ref" ],
        [ "card_reference", "Card Ref" ],
        [ "gateway_reference", "Gateway Ref" ],
        [ "ota_reference", "OTA Ref" ],
        [ "reference", "Reference" ],
        [ "auth_code", "Auth" ],
        [ "authorization_code", "Auth" ],
        [ "gateway_payment_id", "Gateway Ref" ],
        [ "payment_transaction_id", "Gateway Ref" ],
        [ "refund_request_id", "Refund Ref" ]
      ].freeze

      attr_reader :booking, :hotel, :folio, :revision, :invoice_document, :receivable

      def initialize(folio: nil, invoice: nil, receivable: nil, printed_by: nil, revision_number: nil)
        @invoice_document = invoice || folio&.invoice
        @folio = folio || @invoice_document&.booking_folio
        @booking = @folio&.booking
        @hotel = @folio&.hotel
        @receivable = receivable || @invoice_document&.receivable || @folio&.receivable || @folio&.ar_invoice
        @revision_number = revision_number.presence&.to_i
        @printed_by = printed_by
        @legend = {}
      end

      def call
        resolve_revision!
        validate_invoice!
        self
      end

      def document_title
        direct_bill? ? "ACCOUNTS RECEIVABLE INVOICE" : "FOLIO INVOICE"
      end

      def pdf_title
        "#{direct_bill? ? 'AR' : 'Folio'} Invoice - #{invoice_number}"
      end

      def metadata_left
        guest_folio_detail_rows
      end

      def metadata_right
        booking_stay_detail_rows
      end

      def hotel_info_rows
        [
          [ "Hotel Name", snapshot_or_live("hotel", "name") { hotel.name }.presence ],
          [ "Address", hotel_address ],
          [ "Contact", hotel_contact ]
        ].select { |_label, value| value.present? }
      end

      def guest_folio_detail_rows
        return corporate_folio_detail_rows if corporate_payer?

        [
          [ "Guest Name", guest_value(snapshot_or_live("booking", "guest_name") { booking.guest_name }) ],
          [ "Nationality", guest_value(snapshot_or_live("booking", "guest_country") { booking.guest_country }) ],
          [ "Invoice No", invoice_number ],
          [ "Cashier", printed_by ],
          [ "Currency", currency ]
        ]
      end

      def payer_section_title
        corporate_payer? ? "PAYER / FOLIO DETAILS" : "GUEST / FOLIO DETAILS"
      end

      def booking_stay_detail_rows
        [
          [ "Confirm No", guest_value(snapshot_or_live("booking", "confirmation_token") { booking.confirmation_token }) ],
          [ "Folio Account Reference", folio_account_reference ],
          [ "Folio Reference", folio_reference ],
          [ "Room No / Type", room_summary ],
          [ "Arrival", format_datetime(snapshot_or_live("booking", "check_in") { booking.check_in }) ],
          [ "Departure", format_datetime(snapshot_or_live("booking", "check_out") { booking.check_out }) ]
        ]
      end

      def transaction_rows
        @transaction_rows ||= build_transaction_rows
      end

      def summary_rows
        @summary_rows ||= build_summary_rows
      end

      def legend_rows
        transaction_rows
        @legend.sort_by { |code, _label| code.to_s }.map { |code, label| [ code, label ] }
      end

      def notes
        rows = []
        rows << "SST is not applied on top of Tourism Tax." if sst_present? && tourism_tax_present?
        rows << "Service Charge is shown separately from government tax." if service_charge_present?

        payment_note = payment_note_text
        rows << payment_note if payment_note.present?
        rows
      end

      def printed_by
        @printed_by.presence || transaction_users.first&.name.presence || "-"
      end

      def currency
        snapshot_or_live("folio", "currency") { folio.currency }.presence || hotel.default_currency.presence || "MYR"
      end

      def legacy_generated?
        invoice_document.legacy? || @snapshot["legacy_generated"] == true
      end

      def direct_bill?
        invoice_document&.kind_direct_bill?
      end

      def current_payment_status_rows
        return [] unless direct_bill? && receivable.present?

        [
          [ "Status", receivable.status.humanize ],
          [ "Original Amount", amount(receivable.amount) ],
          [ "Paid Amount", amount(receivable.paid_amount) ],
          [ "Outstanding Amount", amount(receivable.outstanding_amount) ],
          [ "Status as of", Time.current.strftime("%d %b %Y %H:%M") ]
        ]
      end

      def total_due
        active_transactions.select { |transaction| transaction.charge? || transaction.adjustment? }
                           .sum { |transaction| transaction.amount.to_d }
      end

      def total_payments
        active_transactions.select(&:payment?).sum { |transaction| transaction.amount.to_d }
      end

      def balance
        total_due - total_payments
      end

      def money(amount)
        "#{currency} #{format_amount(amount)}"
      end

      def credit_money(amount)
        "(#{currency} #{format_amount(amount.to_d.abs)})"
      end

      def amount(amount)
        format_amount(amount)
      end


      def credit_amount(amount)
        "(#{format_amount(amount.to_d.abs)})"
      end

      private

      def corporate_folio_detail_rows
        terms = folio.booking_billing_party&.billing_terms
        account_type = snapshot_or_live("payer", "account_type") do
          folio.booking_billing_party&.account_type.presence || folio.hotel_corporate_account&.account_type
        end
        rows = [
          [ "Corporate Payer", guest_value(snapshot_or_live("payer", "name") { document_live_payer_name }) ],
          [ "Account Type", account_type.to_s.humanize.presence || "-" ],
          [ "Purchase Order", guest_value(snapshot_or_live("payer", "purchase_order_reference") { terms&.purchase_order_reference }) ],
          [ "Authorization", guest_value(snapshot_or_live("payer", "authorization_reference") { terms&.authorization_reference }) ],
          [ "Invoice No", invoice_number ],
          [ "Cashier", printed_by ],
          [ "Currency", currency ]
        ]
        if direct_bill?
          days = snapshot_or_live("payer", "payment_terms_days") { receivable&.hotel_corporate_account&.payment_terms_days }
          terms_label = days.to_i.zero? ? "Due on receipt" : "Net #{days.to_i} days"
          rows.insert(4, [ "Issue Date", invoice_document.issued_on.strftime("%d %b %Y") ])
          rows.insert(5, [ "Due Date", receivable.due_on.strftime("%d %b %Y") ])
          rows.insert(6, [ "Payment Terms", terms_label ])
        end
        rows
      end

      def corporate_payer?
        snapshot_or_live("payer", "type") { folio.payer_type } == "company"
      end

      def document_live_payer_name
        folio.booking_billing_party&.display_name.presence ||
          folio.hotel_corporate_account&.corporate_account&.name.presence ||
          booking.guest_name
      end

      def resolve_revision!
        raise UnavailableError, "Folio has no issued invoice." if invoice_document.blank?

        @revision = if @revision_number.present?
          invoice_document.revisions.find_by(revision_number: @revision_number)
        else
          invoice_document.current_revision
        end
        raise UnavailableError, "Invoice revision is unavailable." if revision.blank?
        @snapshot = revision.snapshot.to_h.deep_stringify_keys
      end

      def validate_invoice!
        return if @revision_number.present?
        return if direct_bill? && invoice_document.finalized?
        return if folio.closed? && invoice_document.finalized?

        raise UnavailableError, "Invoice is unavailable while the folio is open or under correction."
      end

      def build_transaction_rows
        invoice_transactions.map { |transaction| transaction_row(transaction) }.compact
      end

      def build_summary_rows
        rows = []
        rows << SummaryRow.new(label: "Room Revenue, net", amount: room_revenue)
        rows << SummaryRow.new(label: "F&B / Other Revenue, net", amount: other_revenue) unless other_revenue.zero?
        rows << SummaryRow.new(label: "Service Charge", amount: service_charge_total) unless service_charge_total.zero?
        rows << SummaryRow.new(label: "SST 8% - Rooms", amount: sst_room_total) unless sst_room_total.zero?
        rows << SummaryRow.new(label: "SST 6% - F&B / Other", amount: sst_other_total) unless sst_other_total.zero?
        rows << SummaryRow.new(label: tourism_tax_label, amount: tourism_tax_total) unless tourism_tax_total.zero?
        rows << SummaryRow.new(label: "Adjustments", amount: adjustment_total) unless adjustment_total.zero?
        rows << SummaryRow.new(label: "Total Due", amount: total_due, emphasis: true)
        rows << SummaryRow.new(label: "Total Payments", amount: total_payments, credit: true)
        rows << SummaryRow.new(label: "Balance", amount: balance, emphasis: true)
        rows
      end

      def transaction_row(transaction, children: [])
        code, label = display_code_and_label(transaction)
        @legend[code] ||= label
        TransactionRow.new(
          date: format_date(transaction.posting_date),
          code: code,
          description: display_description(transaction),
          secondary_description: secondary_description_for(transaction, children),
          quantity: quantity_for(transaction),
          net: net_amount_for(transaction, children),
          charges: charges_amount_for(transaction, children),
          gross: gross_amount_for(transaction, children),
          kind: transaction.transaction_type
        )
      end

      def secondary_description_for(transaction, children)
        includes = included_charge_summary(children)
        return includes if includes.present?

        payment_reference(transaction)
      end

      def included_charge_summary(children)
        return if children.blank?

        summaries = children.map { |child| "#{display_description(child)} #{format_amount(child.amount)}" }
        "Includes: #{summaries.join(' · ')}"
      end

      def display_code_and_label(transaction)
        code = transaction_code(transaction)
        label = transaction_label(transaction)
        [ code, label ]
      end

      def transaction_code(transaction)
        return derived_tax_transaction_code(transaction) if tax_transaction?(transaction)

        transaction.transaction_code&.code.presence || payment_code(transaction) || FALLBACK_CODES.dig(transaction.category, 0) || transaction.category.to_s.upcase
      end

      def transaction_label(transaction)
        tax_name = tax_line(transaction)["name"].presence if tax_transaction?(transaction)
        tax_name || transaction.transaction_code&.name.presence || payment_label(transaction) || FALLBACK_CODES.dig(transaction.category, 1) || transaction.category.to_s.humanize
      end

      def display_description(transaction)
        return payment_description(transaction) if transaction.payment?
        return tax_description(transaction) if tax_transaction?(transaction)

        transaction.description.to_s
      end

      def tax_description(transaction)
        tax_line(transaction)["name"].presence || transaction.description.to_s.sub(/\ATax:\s*/i, "").sub(/\s+for\s+.+\z/i, "")
      end

      def payment_description(transaction)
        return "Refund - #{payment_label(transaction)}" if transaction.category == "refund"
        if direct_bill? && transaction.description.present?
          return "Payment - #{transaction.description}"
        end

        "Payment - #{payment_label(transaction)}"
      end

      def payment_label(transaction)
        source = transaction.metadata.to_h["payment_source"].presence
        return PAYMENT_SOURCE_LABELS[source] if PAYMENT_SOURCE_LABELS.key?(source)

        transaction.transaction_code&.name.presence ||
          FALLBACK_CODES.dig(transaction.category, 1) ||
          "Payment"
      end

      def payment_code(transaction)
        return unless transaction.payment?

        source = transaction.metadata.to_h["payment_source"].to_s
        case source
        when "cash" then "PAY-CASH"
        when "bank" then "PAY-BANK"
        when "card" then "PAY-CARD"
        when "gateway" then "PAY-GW"
        when "ota" then "PAY-OTA"
        else
          FALLBACK_CODES.dig(transaction.category, 0) || "PAY"
        end
      end

      def payment_reference(transaction)
        metadata = transaction.metadata.to_h
        refs = PAYMENT_REFERENCE_KEYS.filter_map do |key, label|
          value = metadata[key].presence || metadata.dig("source_references", key).presence
          next if value.blank?

          "#{label}: #{safe_reference(value)}"
        end

        refs.first
      end

      def payment_note_text
        payment = active_transactions.select(&:payment?).find { |transaction| payment_reference(transaction).present? }
        return if payment.blank?

        "#{payment_description(payment)} - #{payment_reference(payment)} - Currency: #{currency}"
      end

      def quantity_for(transaction)
        return "-" if transaction.payment?
        return "1" if tourism_tax_transaction?(transaction)
        return "-" if tax_transaction?(transaction)
        return "-" if transaction.adjustment?

        "1"
      end

      def net_amount_for(transaction, children = [])
        return nil unless transaction.charge? && !tax_transaction?(transaction)

        transaction.amount.to_d
      end

      def charges_amount_for(transaction, children = [])
        child_total = children.sum { |child| child.amount.to_d }
        return child_total unless child_total.zero?
        return transaction.amount.to_d if transaction.charge? && tax_transaction?(transaction)

        nil
      end

      def gross_amount_for(transaction, children = [])
        transaction.amount.to_d + children.sum { |child| child.amount.to_d }
      end

      def invoice_transactions
        @invoice_transactions ||= active_transactions.sort_by do |transaction|
          [ presentation_bucket(transaction), transaction.posting_date, transaction.created_at, transaction.id ]
        end
      end

      def presentation_bucket(transaction)
        return 3 if transaction.payment? && transaction.category == "refund"
        return 2 if transaction.payment?
        return 1 if transaction.charge? || transaction.adjustment?

        4
      end

      def attached_children_for(transaction)
        return [] unless transaction.charge? || transaction.adjustment?

        child_transactions_by_parent[transaction.id].to_a
      end

      def hidden_generated_child?(transaction)
        generated_child?(transaction) && active_parent_ids.include?(parent_id(transaction))
      end

      def active_transactions
        @active_transactions ||= begin
          records = if snapshot_transactions?
            @snapshot.fetch("transactions").map { |attributes| SnapshotTransaction.new(attributes) }
          else
            folio.folio_transactions
              .includes(:transaction_code, :user)
              .order(:posting_date, :created_at, :id)
              .to_a
          end
          records.reject { |transaction| hidden_reversal_noise?(transaction) }
        end
      end

      def hidden_reversal_noise?(transaction)
        transaction.voided_by_transaction_id.present? || transaction.reversal_of_transaction_id.present?
      end

      def generated_child?(transaction)
        parent_id(transaction).present?
      end

      def child_transactions_by_parent
        @child_transactions_by_parent ||= active_transactions
          .select { |transaction| parent_id(transaction).present? }
          .group_by { |transaction| parent_id(transaction) }
      end

      def active_parent_ids
        @active_parent_ids ||= active_transactions.map(&:id).to_set
      end

      def tax_transaction?(transaction)
        transaction.category == "tax"
      end

      def tax_line(transaction)
        transaction.metadata.to_h["tax_line"].to_h
      end

      def service_charge_transaction?(transaction)
        text = [ tax_line(transaction)["name"], transaction.description, transaction_code(transaction) ].join(" ").downcase
        text.include?("service charge") || text.include?("svc")
      end

      def sst_transaction?(transaction)
        text = [ tax_line(transaction)["type"], tax_line(transaction)["name"], transaction.description, transaction_code(transaction) ].join(" ").downcase
        text.include?("sst") || text.include?("service tax")
      end

      def tourism_tax_transaction?(transaction)
        text = [ tax_line(transaction)["type"], tax_line(transaction)["name"], transaction.description, transaction_code(transaction) ].join(" ").downcase
        text.include?("tourism")
      end

      def parent_transaction_for(transaction)
        transaction_parent_id = parent_id(transaction)
        return if transaction_parent_id.blank?

        active_transactions.find { |candidate| candidate.id == transaction_parent_id }
      end

      def source_transaction_code_for(transaction)
        parent = parent_transaction_for(transaction)
        source_id = tax_line(transaction)["source_transaction_code_id"].presence ||
          transaction.metadata.to_h["source_transaction_code_id"].presence ||
          (parent.transaction_code_id if parent.respond_to?(:transaction_code_id))
        return parent&.transaction_code if source_id.blank?

        transaction_codes_by_id[source_id.to_i]
      end

      def derived_tax_transaction_code(transaction)
        child_code = tax_line(transaction)["transaction_code_code"].presence || transaction.transaction_code&.code.presence
        source_code = source_transaction_code_for(transaction)&.code.presence
        return "#{source_code}_#{child_code}" if source_code.present? && child_code.present?

        child_code || transaction.transaction_code&.code.presence || FALLBACK_CODES.dig(transaction.category, 0) || transaction.category.to_s.upcase
      end

      def source_transaction_category(transaction)
        parent_transaction_for(transaction)&.category.presence || source_transaction_code_for(transaction)&.category
      end

      def transaction_codes_by_id
        @transaction_codes_by_id ||= snapshot_transactions? ? {} : hotel.transaction_codes.index_by(&:id)
      end

      def parent_id(transaction)
        transaction.metadata.to_h["parent_folio_transaction_id"].presence&.to_i
      end

      def room_revenue
        active_transactions.select { |transaction| transaction.charge? && transaction.category == "accommodation" }
                           .sum { |transaction| transaction.amount.to_d }
      end

      def other_revenue
        active_transactions.select do |transaction|
          transaction.charge? && !tax_transaction?(transaction) && transaction.category != "accommodation"
        end.sum { |transaction| transaction.amount.to_d }
      end

      def adjustment_total
        active_transactions.select(&:adjustment?).sum { |transaction| transaction.amount.to_d }
      end

      def service_charge_total
        active_transactions.select { |transaction| tax_transaction?(transaction) && service_charge_transaction?(transaction) }
                           .sum { |transaction| transaction.amount.to_d }
      end

      def sst_room_total
        active_transactions.select do |transaction|
          tax_transaction?(transaction) &&
            sst_transaction?(transaction) &&
            source_transaction_category(transaction) == "accommodation"
        end.sum { |transaction| transaction.amount.to_d }
      end

      def sst_other_total
        active_transactions.select do |transaction|
          tax_transaction?(transaction) &&
            sst_transaction?(transaction) &&
            source_transaction_category(transaction) != "accommodation"
        end.sum { |transaction| transaction.amount.to_d }
      end

      def tourism_tax_total
        active_transactions.select { |transaction| tax_transaction?(transaction) && tourism_tax_transaction?(transaction) }
                           .sum { |transaction| transaction.amount.to_d }
      end

      def tourism_tax_label
        "Tourism Tax"
      end

      def service_charge_present?
        !service_charge_total.zero?
      end

      def sst_present?
        !(sst_room_total + sst_other_total).zero?
      end

      def tourism_tax_present?
        !tourism_tax_total.zero?
      end

      def transaction_users
        active_transactions.filter_map(&:user).uniq
      end

      def room_summary
        rooms = if @snapshot.key?("rooms")
          Array(@snapshot["rooms"]).map do |room|
            room = room.to_h.stringify_keys
            "#{room["room_number"].presence || "TBA"} / #{room["room_type"].presence || "Room"}"
          end
        else
          booking.booking_rooms.includes(:room_type).map do |room|
            type_name = room.room_type_snapshot["name"].presence || room.room_type&.name || "Room"
            room_number = room.room_number.presence || "TBA"
            "#{room_number} / #{type_name}"
          end
        end

        rooms.presence&.join(", ") || "-"
      end

      def hotel_address
        values = if @snapshot["hotel"].is_a?(Hash)
          %w[address city country].map { |key| @snapshot["hotel"][key] }
        else
          [ hotel.address, hotel.city, hotel.country ]
        end
        values.filter_map(&:presence).uniq.join(", ").presence
      end

      def hotel_contact
        values = if @snapshot["hotel"].is_a?(Hash)
          %w[contact_phone contact_email].map { |key| @snapshot["hotel"][key] }
        else
          [ hotel.contact_phone, hotel.contact_email ]
        end
        values.filter_map(&:presence).join(" · ").presence
      end

      def guest_value(value)
        value.presence || "-"
      end

      def invoice_number
        revision.document_reference
      end

      def folio_account_reference
        snapshot_or_live("folio", "folio_account_reference") { booking.folio_account_reference_display }.presence || booking.formatted_folio_number.presence || "-"
      end

      def folio_reference
        snapshot_or_live("folio", "folio_reference") { folio.folio_reference_display }.presence || folio_account_reference
      end

      def format_date(value)
        return "-" if value.blank?

        value.to_date.strftime("%d %b %y")
      end

      def format_datetime(value)
        return "-" if value.blank?

        parsed = value.respond_to?(:in_time_zone) ? value : Time.zone.parse(value.to_s)
        parsed.in_time_zone(invoice_time_zone).strftime("%d %b %Y %H:%M")
      end

      def format_amount(amount)
        ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", amount.to_d))
      end

      def safe_reference(value)
        value.to_s.gsub(/[^\w\-*]/, "").first(40)
      end

      def snapshot_transactions?
        @snapshot["transactions"].is_a?(Array)
      end

      def snapshot_value(*keys)
        @snapshot&.dig(*keys)
      end

      def snapshot_or_live(section, key)
        values = @snapshot[section]
        return values[key] if values.is_a?(Hash) && values.key?(key)

        yield
      end

      def invoice_time_zone
        snapshot_or_live("hotel", "time_zone") { hotel.hotel_time_zone }.presence || Time.zone.name
      end
    end
  end
end
