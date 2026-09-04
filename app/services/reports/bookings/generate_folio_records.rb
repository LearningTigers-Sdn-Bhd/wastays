# frozen_string_literal: true

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

      SummaryRow = Struct.new(:label, :amount, :credit, :variant, keyword_init: true)
      SnapshotCode = Data.define(:code, :name)
      SnapshotUser = Data.define(:name)

      class SnapshotTransaction
        attr_reader :id, :transaction_type, :category, :description, :amount,
          :currency, :posting_date, :created_at, :metadata,
          :reversal_of_transaction_id, :voided_by_transaction_id,
          :transaction_code, :user,
          :source_transaction_code, :source_transaction_category

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
          @source_transaction_code = attributes["source_transaction_code"]
          @source_transaction_category = attributes["source_transaction_category"]
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

        def posted_transaction_code
          transaction_code&.code
        end

        def posted_transaction_code_name
          transaction_code&.name
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

      # What a tax was charged on, as the tax line itself records it. Every posted room tax
      # carries one of these.
      ROOM_TAX_BASES = %w[nightly_room_charge room_night].freeze

      PdfTheme = HotelPortal::Reports::Exports::PdfTheme

      # What the frame needs of a hotel, taken from the invoice's own snapshot.
      SnapshotHotel = Struct.new(:name, :address, :city, :country, :icon, :hotel_time_zone,
        :fixed_line_number, :contact_phone, :contact_email, keyword_init: true)

      attr_reader :booking, :hotel, :folio, :revision, :invoice_document, :receivable

      def initialize(folio: nil, invoice: nil, receivable: nil, printed_by: nil, revision_number: nil)
        @invoice_document = invoice || folio&.invoice
        @folio = folio || @invoice_document&.booking_folio
        @booking = @folio&.booking
        @hotel = @folio&.hotel
        @receivable = receivable || @invoice_document&.receivable || @folio&.receivable || @folio&.ar_invoice
        @revision_number = revision_number.presence&.to_i
        @printed_by = printed_by
      end

      def call
        resolve_revision!
        validate_invoice!
        self
      end

      def invoice_number
        revision.document_reference
      end

      # Sentence case: the frame upcases an eyebrow itself. An SST-registered issuer has
      # to call the document a tax invoice, and the designation leads because that is the
      # part with force; which of our two invoices it is follows it.
      def document_kind
        kind = direct_bill? ? "Accounts receivable" : "Folio"
        sst_registered? ? "Tax invoice · #{kind}" : "#{kind} invoice"
      end

      def sst_registered?
        snapshot_or_live("hotel", "sst_enabled") { hotel.sst_enabled }.present?
      end

      def pdf_title
        "#{direct_bill? ? 'AR' : 'Folio'} Invoice - #{invoice_number}"
      end

      # The three parties to the document, for PdfPartyBlocks. Every entry is labelled and
      # every label sits above its value, so the three columns read the same way; blank
      # values are dropped by the block, so a fact the snapshot never captured costs a line.
      def party_blocks
        [
          { heading: payer_heading, entries: bill_to_entries },
          { heading: "Invoice details", entries: invoice_detail_entries },
          { heading: "Stay details", entries: stay_detail_entries }
        ]
      end

      def payer_heading
        corporate_payer? ? "Bill to (payer)" : "Bill to"
      end

      def bill_to_entries
        return corporate_bill_to_entries if corporate_payer?

        [
          [ "Guest", snapshot_or_live("booking", "guest_name") { booking.guest_name } ],
          [ "Billing address", guest_billing_address ],
          [ "Contact email", snapshot_payer_value("contact_email") ],
          [ "Contact phone", snapshot_payer_value("contact_phone") ]
        ]
      end

      def guest_billing_address
        payer = @snapshot["payer"]
        if payer.is_a?(Hash) && payer.key?("billing_address")
          return PostalAddresses::Presenter.from_snapshot(payer["billing_address"]).display.presence || "Not provided"
        end

        values = @snapshot["booking"]
        return "Not provided" unless values.is_a?(Hash)

        legacy_address = {
          address_line1: values["guest_home_address"],
          city: values["guest_city"],
          state: PostalAddresses::Presenter.printable_state(values["guest_state_code"]),
          postal_code: values["guest_postal_code"],
          country: values["guest_address_country"].presence || values["guest_country"]
        }
        PostalAddresses::Presenter.new(legacy_address).display.presence || "Not provided"
      end

      def snapshot_payer_value(key)
        payer = @snapshot["payer"]
        payer[key] if payer.is_a?(Hash) && payer.key?(key)
      end

      def invoice_detail_entries
        # No account reference: the folio number is that reference plus the window, so
        # printing both tells the payer the same thing twice. The ledger keeps it, where
        # how the account is filed is the point.
        entries = [
          # The date the invoice was issued, not the date this copy was printed. A tax
          # document is dated once; the printing is drawn apart from these, at the foot.
          [ "Issue date", PdfTheme.format_date(invoice_document.issued_on) ],
          [ "Issued by", printed_by ],
          [ "Folio no.", folio_reference ]
        ]
        entries << [ "Revision", revision.revision_number.to_s ] if revised?
        entries.concat(direct_bill_term_entries) if direct_bill?
        entries
      end

      def stay_detail_entries
        [
          [ "Booking ref", snapshot_or_live("booking", "reservation_reference") { booking.formatted_reservation_number } ],
          [ "Confirm no.", snapshot_or_live("booking", "confirmation_token") { booking.confirmation_token } ],
          [ "Room / type", room_summary ],
          [ "Arrival", format_datetime(snapshot_or_live("booking", "check_in") { booking.check_in }) ],
          [ "Departure", format_datetime(snapshot_or_live("booking", "check_out") { booking.check_out }) ]
        ]
      end

      # The frame draws the masthead from whatever answers to these, so an issued invoice
      # can wear the hotel it was issued by rather than the hotel as it is named today.
      # The three parts of the address go over separately: the frame joins them, and drops
      # the ones the address line already names. The logo is not snapshotted, so it comes
      # from the live record.
      def pdf_hotel
        SnapshotHotel.new(
          name: snapshot_or_live("hotel", "name") { hotel.name }.presence || hotel.name,
          address: hotel_value("address") { hotel.address },
          city: hotel_value("city") { hotel.city },
          country: hotel_value("country") { hotel.country },
          icon: hotel.try(:icon), hotel_time_zone: invoice_time_zone,
          # Read live, and the only part of the masthead that is. It exists so whoever holds
          # the bill can reach the hotel about it, and a number the hotel stopped answering
          # serves nobody — where its name, address and registrations are what they were when
          # it billed, and have to stay that. The snapshot keeps capturing them as a record of
          # the day; it is simply not what the masthead prints.
          fixed_line_number: hotel.fixed_line_number,
          contact_phone: hotel.contact_phone,
          contact_email: hotel.contact_email
        )
      end

      # Sits under the address rather than among the invoice details: these identify the
      # party issuing the document, not the document. Read from the issue-time snapshot,
      # unlike the contact line above — a registration is what it was when the hotel
      # billed, and has to stay that.
      def hotel_identifier_line
        Reports::HotelIdentifierLine.call(
          tin: hotel_value("tin") { hotel.tin },
          sst: hotel_value("sst_registration_number") { hotel.sst_registration_number },
          tourism_tax: hotel_value("tourism_tax_registration_number") { hotel.tourism_tax_registration_number }
        )
      end

      def transaction_rows
        @transaction_rows ||= build_transaction_rows
      end

      # The two halves of the document, already grouped by #presentation_bucket. Split so
      # each can be tabled under a heading of its own: what the stay cost, then what was
      # paid against it.
      def charge_rows = transaction_rows.reject { |row| row.kind == "payment" }

      def payment_rows = transaction_rows.select { |row| row.kind == "payment" }

      def summary_rows
        @summary_rows ||= build_summary_rows
      end

      def notes
        rows = []
        rows << superseded_note if revised?
        rows << "SST is not applied on top of Tourism Tax." if sst_present? && tourism_tax_present?
        rows << "Service Charge is shown separately from government tax." if service_charge_present?
        rows
      end

      # When this copy was printed. Set against the issue date rather than beside it: a
      # reprint changes this and nothing else on the document.
      def printed_at
        format_datetime(Time.current)
      end

      # A reissued invoice has to say so on its face. The document reference carries the
      # revision, but a reader holding one sheet cannot tell a suffix from a serial.
      def revised?
        revision.revision_number > 1
      end

      def superseded_note
        superseded = invoice_document.revisions.find_by(revision_number: revision.revision_number - 1)
        return "Revision #{revision.revision_number} of this invoice." if superseded.blank?

        "Revision #{revision.revision_number} of this invoice; it supersedes #{superseded.document_reference}."
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
          [ "Status as of", format_datetime(Time.current) ]
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

      # A closed folio and an unpaid receivable both end on a line called Balance, and the
      # figure alone does not say which. The label says it, and the row takes the alert
      # colour only while money is still owed.
      def settled? = balance.zero?

      def balance_label = settled? ? "Balance settled" : "Balance due"

      # The first thing a reader looks for, answered beside the invoice number rather than
      # eight inches down the page. Read from the issued figures like every other total on
      # the document, so a reprint cannot change what it says.
      def status_badge
        settled? ? { label: "Settled", variant: :positive } : { label: "Balance due", variant: :warning }
      end

      def balance_variant = settled? ? :subtotal : :alert

      def amount(amount)
        format_amount(amount)
      end


      def credit_amount(amount)
        "(#{format_amount(amount.to_d.abs)})"
      end

      private

      # A corporate payer has a name but no address anywhere in the schema, so its block
      # carries the references that identify the account instead.
      def corporate_bill_to_entries
        terms = folio.booking_billing_party&.billing_terms
        account_type = snapshot_or_live("payer", "account_type") do
          folio.booking_billing_party&.account_type.presence || folio.hotel_corporate_account&.account_type
        end
        [
          [ "Payer", snapshot_or_live("payer", "name") { document_live_payer_name } ],
          [ "Billing address", corporate_billing_address ],
          [ "Account type", account_type.to_s.humanize.presence ],
          [ "PO ref", snapshot_or_live("payer", "purchase_order_reference") { terms&.purchase_order_reference } ],
          [ "Auth", snapshot_or_live("payer", "authorization_reference") { terms&.authorization_reference } ]
        ]
      end

      # Corporate addresses only come from the issue-time snapshot. An invoice issued
      # before address capture existed remains unchanged when it is printed again.
      def corporate_billing_address
        payer = @snapshot["payer"]
        address = payer["billing_address"] if payer.is_a?(Hash) && payer.key?("billing_address")
        CorporateAccounts::BillingAddressPresenter.new(address || {}).display.presence || "Not provided"
      end

      def direct_bill_term_entries
        days = snapshot_or_live("payer", "payment_terms_days") { receivable&.hotel_corporate_account&.payment_terms_days }
        [
          [ "Due date", PdfTheme.format_date(receivable&.due_on) ],
          [ "Payment terms", days.to_i.zero? ? "Due on receipt" : "Net #{days.to_i} days" ]
        ]
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

      # Sentence case, and no separator inside a label that already has one. "SST 6% - F&B /
      # Other" set beside a figure reads as arithmetic before it reads as a name: the
      # hyphen looks like a minus and the slash like a second one. The rate is charged
      # *on* something, so the label says so.
      def build_summary_rows
        rows = []
        rows << SummaryRow.new(label: "Room revenue, net", amount: room_revenue) unless room_revenue.zero?
        rows << SummaryRow.new(label: "F&B and other revenue, net", amount: other_revenue) unless other_revenue.zero?
        rows << SummaryRow.new(label: "Service charge", amount: service_charge_total) unless service_charge_total.zero?
        rows << SummaryRow.new(label: "SST 8% on rooms", amount: sst_room_total) unless sst_room_total.zero?
        rows << SummaryRow.new(label: "SST 6% on F&B and other", amount: sst_other_total) unless sst_other_total.zero?
        rows << SummaryRow.new(label: tourism_tax_label, amount: tourism_tax_total) unless tourism_tax_total.zero?
        unless adjustment_total.zero?
          # An adjustment that gives money back is a credit and is bracketed like one; a
          # bare minus among bracketed amounts reads as a second convention.
          rows << SummaryRow.new(label: "Adjustments", amount: adjustment_total, credit: adjustment_total.negative?)
        end
        # The tables above end on Total Due and Total Payments, so the summary states the
        # decomposition and the bottom line, and no figure is printed twice.
        rows << SummaryRow.new(variant: :spacer)
        rows << SummaryRow.new(label: balance_label, amount: balance, variant: balance_variant)
        rows
      end

      def transaction_row(transaction)
        code, label = display_code_and_label(transaction)
        TransactionRow.new(
          date: format_date(transaction.posting_date),
          code: code,
          description: display_description(transaction),
          secondary_description: secondary_description_for(transaction),
          quantity: quantity_for(transaction),
          net: net_amount_for(transaction),
          charges: charges_amount_for(transaction),
          gross: gross_amount_for(transaction),
          kind: transaction.transaction_type
        )
      end

      # The reference keys are payment-shaped — a receipt, an auth code, a gateway id — and
      # a charge that happens to carry one in its metadata was printing it under the
      # description as though the guest had paid for something twice.
      def secondary_description_for(transaction)
        return unless transaction.payment?

        payment_reference(transaction)
      end

      def display_code_and_label(transaction)
        code = transaction_code(transaction)
        label = transaction_label(transaction)
        [ code, label ]
      end

      def transaction_code(transaction)
        return derived_tax_transaction_code(transaction) if tax_transaction?(transaction)

        transaction.posted_transaction_code.presence || payment_code(transaction) || FALLBACK_CODES.dig(transaction.category, 0) || transaction.category.to_s.upcase
      end

      def transaction_label(transaction)
        tax_name = tax_line(transaction)["name"].presence if tax_transaction?(transaction)
        tax_name || transaction.posted_transaction_code_name.presence || payment_label(transaction) || FALLBACK_CODES.dig(transaction.category, 1) || transaction.category.to_s.humanize
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

        transaction.posted_transaction_code_name.presence ||
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

      def quantity_for(transaction)
        return "-" if transaction.payment?
        return "1" if tourism_tax_transaction?(transaction)
        return "-" if tax_transaction?(transaction)
        return "-" if transaction.adjustment?

        "1"
      end

      # A charge posts its own amount as net, a tax posts its amount as the charge on top,
      # and every row is gross of itself. Nothing is folded into anything.
      def net_amount_for(transaction)
        return nil unless transaction.charge? && !tax_transaction?(transaction)

        transaction.amount.to_d
      end

      def charges_amount_for(transaction)
        return transaction.amount.to_d if transaction.charge? && tax_transaction?(transaction)

        nil
      end

      def gross_amount_for(transaction) = transaction.amount.to_d

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

      # The parent is the fallback whether or not an id was posted. It used to be reached
      # only when no id was posted at all, so a transaction naming its source by an id the
      # lookup could not resolve — which is any of them, once the invoice renders from its
      # snapshot — resolved to nothing while its parent sat there unasked.
      def source_transaction_code_for(transaction)
        parent = parent_transaction_for(transaction)
        source_id = tax_line(transaction)["source_transaction_code_id"].presence ||
          transaction.metadata.to_h["source_transaction_code_id"].presence ||
          (parent.transaction_code_id if parent.respond_to?(:transaction_code_id))

        transaction_codes_by_id[source_id.to_i] || parent&.transaction_code
      end

      # What the tax was levied on, in the order the document can trust it: what the
      # invoice recorded when it was issued, then what the posted tax line names, then the
      # live codes, which a snapshotted invoice cannot reach.
      def source_code(transaction)
        transaction.try(:source_transaction_code).presence ||
          tax_line(transaction)["source_transaction_code_code"].presence ||
          source_transaction_code_for(transaction)&.code.presence
      end

      def derived_tax_transaction_code(transaction)
        child_code = tax_line(transaction)["transaction_code_code"].presence || transaction.posted_transaction_code.presence
        source = source_code(transaction)
        return "#{source}_#{child_code}" if source.present? && child_code.present?

        child_code || transaction.posted_transaction_code.presence || FALLBACK_CODES.dig(transaction.category, 0) || transaction.category.to_s.upcase
      end

      def source_transaction_category(transaction)
        transaction.try(:source_transaction_category).presence ||
          parent_transaction_for(transaction)&.category.presence ||
          source_transaction_code_for(transaction)&.category
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

      # Asked of the tax line first, and of the charge it hangs off only as a fallback. The
      # code lookup behind source_transaction_category is empty for a snapshotted invoice —
      # which is every issued one — so a room tax posted without a parent transaction
      # resolved to no category at all and was counted as F&B. The basis is in the snapshot
      # and says plainly what the tax was charged on.
      def room_tax?(transaction)
        return true if ROOM_TAX_BASES.include?(tax_line(transaction)["basis"].to_s)

        source_transaction_category(transaction) == "accommodation"
      end

      def sst_room_total
        sst_transactions.select { |transaction| room_tax?(transaction) }
                        .sum { |transaction| transaction.amount.to_d }
      end

      def sst_other_total
        sst_transactions.reject { |transaction| room_tax?(transaction) }
                        .sum { |transaction| transaction.amount.to_d }
      end

      # One list, so the two rates are complements and no SST can fall between them.
      def sst_transactions
        @sst_transactions ||= active_transactions.select do |transaction|
          tax_transaction?(transaction) && sst_transaction?(transaction)
        end
      end

      def tourism_tax_total
        active_transactions.select { |transaction| tax_transaction?(transaction) && tourism_tax_transaction?(transaction) }
                           .sum { |transaction| transaction.amount.to_d }
      end

      def tourism_tax_label
        "Tourism tax"
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

      # Named and dashed like the registrations: three contacts run together unlabelled
      # read as one string of digits, and a guest who cannot find a landline on the bill
      # should see that the hotel published none rather than wonder which number is which.
      #
      def folio_account_reference
        snapshot_or_live("folio", "folio_account_reference") { booking.folio_account_reference_display }.presence || booking.formatted_folio_number.presence || "-"
      end

      def folio_reference
        snapshot_or_live("folio", "folio_reference") { folio.folio_reference_display }.presence || folio_account_reference
      end

      def format_date(value)
        return "-" if value.blank?

        PdfTheme.format_date(value.to_date)
      end

      def format_datetime(value)
        return "-" if value.blank?

        parsed = value.respond_to?(:in_time_zone) ? value : Time.zone.parse(value.to_s)
        PdfTheme.format_time(parsed, invoice_time_zone)
      end

      def format_amount(amount)
        PdfTheme.money(amount)
      end

      def safe_reference(value)
        value.to_s.gsub(/[^\w\-*]/, "").first(40)
      end

      def snapshot_transactions?
        @snapshot["transactions"].is_a?(Array)
      end

      def snapshot_or_live(section, key)
        values = @snapshot[section]
        return values[key] if values.is_a?(Hash) && values.key?(key)

        yield
      end

      # A hotel fact as the invoice was issued, falling back to the live record for the
      # invoices whose snapshot was taken before the field was captured.
      def hotel_value(key, &live)
        snapshot_or_live("hotel", key, &live).presence
      end

      def invoice_time_zone
        snapshot_or_live("hotel", "time_zone") { hotel.hotel_time_zone }.presence || Time.zone.name
      end
    end
  end
end
