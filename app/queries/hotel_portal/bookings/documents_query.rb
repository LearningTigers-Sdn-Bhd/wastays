# frozen_string_literal: true

module HotelPortal
  module Bookings
    class DocumentsQuery
      include Rails.application.routes.url_helpers

      Row = Data.define(
        :key,
        :type,
        :number,
        :booking,
        :room,
        :payer,
        :currency,
        :amount,
        :status,
        :issued_at,
        :href,
        :unavailable_reason,
        :historical,
        :context_type
      ) do
        def available?
          href.present?
        end
      end

      TYPE_ORDER = {
        "Folio invoice" => 0,
        "Invoice revision" => 1,
        "AR invoice" => 2,
        "Folio ledger" => 3,
        "Payment receipt" => 4,
        "Deposit receipt" => 5,
        "Group deposit receipt" => 6,
        "AR payment receipt" => 7,
        "Registration card" => 8,
        "Payer statement" => 9
      }.freeze

      def self.call(booking:, group_booking: booking.group_booking, hotel: booking.hotel, user: nil)
        new(booking:, group_booking:, hotel:, user:).call
      end

      def initialize(booking:, group_booking:, hotel:, user:)
        @booking = booking
        @group_booking = group_booking
        @hotel = hotel
        @user = user
      end

      def call
        validate_scope!
        load_records

        rows = folio_rows + receipt_rows + registration_card_rows + statement_rows
        rows.sort_by { |row| [ booking_position(row.booking), TYPE_ORDER.fetch(row.type), row.issued_at || Time.zone.at(0), row.key ] }
      end

      private

      def validate_scope!
        raise ActiveRecord::RecordNotFound unless @booking.hotel_id == @hotel.id
        return if @group_booking.blank?
        raise ActiveRecord::RecordNotFound unless @group_booking.hotel_id == @hotel.id && @booking.group_booking_id == @group_booking.id
      end

      def load_records
        ids = if @group_booking
          @hotel.bookings.where(group_booking_id: @group_booking.id).pluck(:id)
        else
          [ @booking.id ]
        end

        @bookings = @hotel.bookings
          .where(id: ids)
          .includes(
            :guest_registration_card,
            { booking_rooms: :room_type },
            { booking_guests: :guest },
            booking_folios: [
              :booking_room,
              { folio_invoice: :revisions },
              { ar_invoice: { hotel_corporate_account: :corporate_account } },
              { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: :corporate_account } ] },
              { hotel_corporate_account: :corporate_account }
            ]
          )
          .order(:group_position, :id)
          .to_a
        @booking_positions = @bookings.to_h { |booking| [ booking_label(booking), [ booking.group_position || 0, booking.id ] ] }

        @folios = @bookings.flat_map(&:booking_folios)
        @folios_by_id = @folios.index_by(&:id)
        load_transaction_totals
        load_deposits
        load_receipts
      end

      def load_transaction_totals
        totals = FolioTransaction
          .where(booking_folio_id: @folios_by_id.keys)
          .group(:booking_folio_id, :transaction_type)
          .sum(:amount)

        @folio_totals = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }
        totals.each { |(folio_id, type), amount| @folio_totals[folio_id][type] = amount.to_d }
      end

      def load_deposits
        booking_deposits = Deposit.where(hotel_id: @hotel.id, booking_id: @bookings.map(&:id)).includes(:receipt).to_a
        group_deposits = if @group_booking
          Deposit.where(hotel_id: @hotel.id, group_booking_id: @group_booking.id).includes(:receipt).to_a
        else
          []
        end
        @deposits = booking_deposits + group_deposits
      end

      def load_receipts
        transaction_scope = FolioTransaction.where(booking_folio_id: @folios_by_id.keys)
        folio_receipts = Receipt
          .where(hotel_id: @hotel.id, folio_transaction_id: transaction_scope.select(:id))
          .includes(folio_transaction: :booking_folio)
          .to_a

        @ar_invoices = @folios.filter_map(&:ar_invoice)
        @ar_invoices_by_id = @ar_invoices.index_by(&:id)
        ar_payment_ids = ArPaymentAllocation.where(ar_invoice_id: @ar_invoices.map(&:id)).select(:ar_payment_id)
        ar_receipts = Receipt.where(hotel_id: @hotel.id, ar_payment_id: ar_payment_ids).includes(:ar_payment).to_a
        allocation_pairs = ArPaymentAllocation
          .where(ar_invoice_id: @ar_invoices.map(&:id), ar_payment_id: ar_receipts.map(&:ar_payment_id))
          .pluck(:ar_payment_id, :ar_invoice_id)
        @ar_invoice_ids_by_payment_id = allocation_pairs.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(payment_id, invoice_id), grouped|
          grouped[payment_id] << invoice_id
        end

        @folio_receipts = folio_receipts
        @ar_receipts = ar_receipts
      end

      def folio_rows
        @folios.flat_map do |folio|
          [ *folio_invoice_rows(folio), ar_invoice_row(folio), folio_ledger_row(folio) ].compact
        end
      end

      def folio_invoice_rows(folio)
        invoice = folio.folio_invoice
        return [ unavailable_folio_invoice_row(folio) ] unless invoice

        invoice.revisions.map do |revision|
          current = revision.revision_number == invoice.current_revision_number
          current ? current_invoice_row(folio, invoice, revision) : historical_invoice_row(folio, revision)
        end
      end

      def current_invoice_row(folio, invoice, revision)
        reason = case invoice.state
        when "under_correction" then "Invoice under correction"
        when "voided" then "Invoice voided"
        end
        href = if reason.nil?
          hotel_folio_invoice_path(@hotel, folio)
        elsif permission?("view_audit_logs")
          hotel_folio_invoice_revision_path(@hotel, folio, revision.revision_number)
        end

        invoice_row(
          folio:,
          revision:,
          type: "Folio invoice",
          status: invoice.state.humanize,
          href:,
          reason:,
          historical: false
        )
      end

      def historical_invoice_row(folio, revision)
        allowed = permission?("view_audit_logs")
        invoice_row(
          folio:,
          revision:,
          type: "Invoice revision",
          status: "Historical",
          href: (hotel_folio_invoice_revision_path(@hotel, folio, revision.revision_number) if allowed),
          reason: ("Permission required" unless allowed),
          historical: true,
          restricted: !allowed
        )
      end

      def invoice_row(folio:, revision:, type:, status:, href:, reason:, historical:, restricted: false)
        snapshot = revision.snapshot.to_h.stringify_keys
        Row.new(
          "folio-invoice-revision-#{revision.id}",
          type,
          restricted ? "Restricted" : revision.document_reference,
          booking_label(folio.booking),
          room_label(folio),
          restricted ? "Restricted" : invoice_payer(snapshot, folio),
          restricted ? nil : snapshot.dig("totals", "currency").presence || folio.currency,
          restricted ? nil : invoice_amount(snapshot, folio),
          restricted ? "Permission required" : status,
          revision.issued_at,
          href,
          reason,
          historical,
          folio.folio_type.humanize
        )
      end

      def unavailable_folio_invoice_row(folio)
        reason = if folio.ar_invoice
          "Direct Bill uses AR invoice"
        elsif folio.open?
          "Folio still open"
        elsif folio.voided?
          "Folio voided"
        else
          "No invoice has been issued"
        end

        Row.new(
          "folio-invoice-unavailable-#{folio.id}",
          "Folio invoice",
          "Not issued",
          booking_label(folio.booking),
          room_label(folio),
          folio_payer(folio),
          folio.currency,
          invoice_amount({}, folio),
          "Unavailable",
          nil,
          nil,
          reason,
          false,
          folio.folio_type.humanize
        )
      end

      def ar_invoice_row(folio)
        invoice = folio.ar_invoice
        return unless invoice

        allowed = permission?("view_reports")
        Row.new(
          "ar-invoice-#{invoice.id}",
          "AR invoice",
          allowed ? invoice.formatted_invoice_number : "Restricted",
          booking_label(folio.booking),
          room_label(folio),
          allowed ? invoice.corporate_account.name : "Restricted",
          allowed ? invoice.currency : nil,
          allowed ? invoice.amount : nil,
          allowed ? invoice.status.humanize : "Permission required",
          invoice.issued_on&.in_time_zone,
          (pdf_hotel_ar_invoice_path(@hotel, invoice) if allowed),
          ("Permission required" unless allowed),
          false,
          folio.folio_type.humanize
        )
      end

      def folio_ledger_row(folio)
        Row.new(
          "folio-ledger-#{folio.id}",
          "Folio ledger",
          folio.folio_reference_display,
          booking_label(folio.booking),
          room_label(folio),
          folio_payer(folio),
          folio.currency,
          folio_balance(folio),
          folio.status.humanize,
          folio.closed_at || folio.opened_at,
          hotel_folio_ledger_path(@hotel, folio, format: :pdf),
          nil,
          false,
          folio.folio_type.humanize
        )
      end

      def receipt_rows
        rows = @folio_receipts.map { |receipt| folio_receipt_row(receipt) }
        rows.concat(@deposits.filter_map { |deposit| deposit_receipt_row(deposit) })
        rows.concat(@ar_receipts.filter_map { |receipt| ar_receipt_row(receipt) })

        booking_ids_with_receipts = rows.filter_map do |row|
          row.key[/booking-(\d+)/, 1]&.to_i if row.type == "Payment receipt"
        end.to_set
        @bookings.each do |booking|
          next if booking_ids_with_receipts.include?(booking.id)

          rows << Row.new(
            "payment-receipt-unavailable-booking-#{booking.id}",
            "Payment receipt",
            "Not issued",
            booking_label(booking),
            room_label_for_booking(booking),
            primary_guest_name(booking),
            booking.currency,
            nil,
            "Unavailable",
            nil,
            nil,
            "No receipt has been issued",
            false,
            "Payment receipt"
          )
        end
        rows
      end

      def folio_receipt_row(receipt)
        folio = receipt.folio_transaction.booking_folio
        receipt_row(receipt, type: "Payment receipt", booking: folio.booking, room: room_label(folio), payer: receipt_payer(receipt))
      end

      def deposit_receipt_row(deposit)
        receipt = deposit.receipt
        return unless receipt

        type = deposit.group_booking_id? ? "Group deposit receipt" : "Deposit receipt"
        booking = deposit.booking
        receipt_row(
          receipt,
          type:,
          booking:,
          room: booking ? room_label_for_booking(booking) : "Group",
          payer: receipt_payer(receipt),
          group: deposit.group_booking_id?
        )
      end

      def ar_receipt_row(receipt)
        invoices = @ar_invoice_ids_by_payment_id[receipt.ar_payment_id].filter_map { |invoice_id| @ar_invoices_by_id[invoice_id] }
        return if invoices.empty?

        allowed = permission?("view_reports")
        return restricted_ar_receipt_row(receipt, invoices.first) unless allowed
        return multiple_ar_receipt_row(receipt, invoices) if invoices.many?

        receipt_row(
          receipt,
          type: "AR payment receipt",
          booking: invoices.first.booking,
          room: room_label(invoices.first.booking_folio),
          payer: invoices.first.corporate_account.name
        )
      end

      def multiple_ar_receipt_row(receipt, invoices)
        Row.new(
          "ar-payment-receipt-multiple-#{receipt.id}",
          "AR payment receipt",
          receipt.public_number,
          @group_booking ? group_booking_label : "Multiple bookings",
          "Multiple rooms",
          invoices.map { |invoice| invoice.corporate_account.name }.uniq.to_sentence,
          receipt.currency,
          receipt.amount,
          receipt.status.humanize,
          receipt.issued_at,
          receipt_path(receipt.access_token),
          nil,
          false,
          "AR payment receipt"
        )
      end

      def receipt_row(receipt, type:, booking:, room:, payer:, group: false)
        key_owner = group ? "group-#{@group_booking.id}" : "booking-#{booking.id}"
        Row.new(
          "#{type.parameterize}-#{key_owner}-#{receipt.id}",
          type,
          receipt.public_number,
          booking ? booking_label(booking) : group_booking_label,
          room,
          payer,
          receipt.currency,
          receipt.amount,
          receipt.status.humanize,
          receipt.issued_at,
          receipt_path(receipt.access_token),
          nil,
          false,
          type
        )
      end

      def restricted_ar_receipt_row(receipt, invoice)
        Row.new(
          "ar-payment-receipt-booking-#{invoice.booking.id}-#{receipt.id}",
          "AR payment receipt",
          "Restricted",
          booking_label(invoice.booking),
          room_label(invoice.booking_folio),
          "Restricted",
          nil,
          nil,
          "Permission required",
          receipt.issued_at,
          nil,
          "Permission required",
          false,
          "AR payment receipt"
        )
      end

      def registration_card_rows
        allowed = permission?("manage_bookings") || permission?("view_reports")
        @bookings.map do |booking|
          card = booking.guest_registration_card
          Row.new(
            "registration-card-booking-#{booking.id}",
            "Registration card",
            allowed ? booking.guest_registration_card_number_display.presence || "Not issued" : "Restricted",
            booking_label(booking),
            room_label_for_booking(booking),
            primary_guest_name(booking),
            nil,
            nil,
            allowed ? card&.status&.humanize || "Not issued" : "Permission required",
            card&.created_at,
            (hotel_booking_guest_registration_card_path(@hotel, booking) if allowed),
            ("Permission required" unless allowed),
            false,
            "Registration card"
          )
        end
      end

      def statement_rows
        invoices_by_account_and_currency = @ar_invoices.group_by { |invoice| [ invoice.hotel_corporate_account, invoice.currency ] }
        invoices_by_account_and_currency.map do |(account, currency), _invoices|
          allowed = permission?("view_reports")
          Row.new(
            "payer-statement-#{account.id}-#{currency}",
            "Payer statement",
            allowed ? "Current statement" : "Restricted",
            group_booking_label,
            "All rooms",
            allowed ? account.corporate_account.name : "Restricted",
            allowed ? currency : nil,
            nil,
            allowed ? "Available" : "Permission required",
            nil,
            (hotel_ar_statement_path(@hotel, account, format: :pdf, currency:, report_type: "detail") if allowed),
            ("Permission required" unless allowed),
            false,
            "Payer statement"
          )
        end
      end

      def invoice_amount(snapshot, folio)
        totals = snapshot["totals"].to_h
        return totals["charges"].to_d + totals["adjustments"].to_d if totals.key?("charges")

        @folio_totals[folio.id]["charge"] + @folio_totals[folio.id]["adjustment"]
      end

      def folio_balance(folio)
        totals = @folio_totals[folio.id]
        totals["charge"] - totals["payment"] + totals["adjustment"]
      end

      def invoice_payer(snapshot, folio)
        snapshot.dig("payer", "name").presence || folio_payer(folio)
      end

      def folio_payer(folio)
        folio.booking_billing_party&.display_name.presence ||
          folio.hotel_corporate_account&.corporate_account&.name.presence ||
          primary_guest_name(folio.booking)
      end

      def receipt_payer(receipt)
        receipt.payer_snapshot.to_h.stringify_keys["name"].presence || "Payer unavailable"
      end

      def primary_guest_name(booking)
        booking.booking_guests.find(&:primary?)&.guest&.name.presence || booking.guest_name.presence || "Guest unavailable"
      end

      def booking_label(booking)
        booking.formatted_reservation_number.presence || booking.confirmation_token
      end

      def group_booking_label
        @group_booking&.formatted_reservation_number.presence || booking_label(@booking)
      end

      def room_label(folio)
        room = folio.booking_room || folio.booking.booking_rooms.first
        room_label_for(room)
      end

      def room_label_for_booking(booking)
        room_label_for(booking.booking_rooms.first)
      end

      def room_label_for(room)
        return "Unassigned" unless room

        [ room.room_number.presence && "Room #{room.room_number}", room.room_type&.name ].compact_blank.join(" · ").presence || "Unassigned"
      end

      def booking_position(label)
        @booking_positions.fetch(label, [ -1, 0 ])
      end

      def permission?(slug)
        @permissions ||= {}
        return @permissions[slug] if @permissions.key?(slug)

        @permissions[slug] = !!@user&.has_permission?(slug, hotel: @hotel)
      end
    end
  end
end
