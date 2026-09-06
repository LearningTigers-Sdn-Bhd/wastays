# frozen_string_literal: true

module Reports
  module AccountsReceivable
    class GenerateStatementRecords
      InvalidStatementError = Class.new(StandardError)

      LedgerRow = Struct.new(
        :effective_date,
        :record_type,
        :reference,
        :description,
        :due_on,
        :debit,
        :credit,
        :balance,
        keyword_init: true
      )

      LedgerActivity = Data.define(
        :sort_key,
        :effective_date,
        :record_type,
        :source,
        :due_on,
        :debit,
        :credit,
        :balance
      )

      class Ledger
        def initialize(activities, row_builder)
          @activities = activities
          @row_builder = row_builder
          @row_cache = {}
        end

        def count
          @activities.size
        end

        def page(offset:, limit:)
          (@activities[offset, limit] || []).map { |activity| materialize(activity) }
        end

        def all
          @all ||= page(offset: 0, limit: count)
        end

        private

        def materialize(activity)
          @row_cache[activity.object_id] ||= @row_builder.call(activity)
        end
      end

      InvoiceDetail = Struct.new(
        :invoice,
        :billing_name,
        :bill_no,
        :check_in,
        :check_out,
        :room_label,
        :balance,
        :line_items,
        keyword_init: true
      )

      LineItem = Struct.new(
        :date,
        :description,
        :charge,
        :credit,
        :balance,
        keyword_init: true
      )

      AgingTotals = Struct.new(
        :current,
        :days_1_30,
        :days_31_60,
        :days_61_90,
        :days_over_90,
        keyword_init: true
      ) do
        def total
          current.to_d + days_1_30.to_d + days_31_60.to_d + days_61_90.to_d + days_over_90.to_d
        end
      end

      Result = Struct.new(
        :hotel,
        :hotel_corporate_account,
        :corporate_account,
        :contact_email,
        :start_date,
        :end_date,
        :currency,
        :available_currencies,
        :opening_balance,
        :period_invoices,
        :period_payments,
        :closing_balance,
        :unapplied_credit,
        :aging,
        :ledger,
        :invoice_details,
        :notes,
        keyword_init: true
      ) do
        def ledger_rows
          ledger.all
        end
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(hotel:, hotel_corporate_account:, start_date:, end_date:, currency: nil, include_invoice_details: false)
        @hotel = hotel
        @hotel_corporate_account = hotel_corporate_account
        @start_date = parse_date(start_date, "Start date")
        @end_date = parse_date(end_date, "End date")
        @requested_currency = currency.to_s.presence
        @include_invoice_details = include_invoice_details
      end

      def call
        validate_relationship!
        validate_period!
        validate_currency!

        Result.new(
          hotel: @hotel,
          hotel_corporate_account: @hotel_corporate_account,
          corporate_account: corporate_account,
          contact_email: contact_email,
          start_date: @start_date,
          end_date: @end_date,
          currency: selected_currency,
          available_currencies: available_currencies,
          opening_balance: opening_balance,
          period_invoices: period_invoice_total,
          period_payments: period_payment_total,
          closing_balance: closing_balance,
          unapplied_credit: unapplied_credit,
          aging: aging_totals,
          ledger: ledger,
          invoice_details: invoice_details,
          notes: notes
        )
      end

      private

      def parse_date(value, label)
        value.to_date
      rescue NoMethodError, Date::Error, ArgumentError
        raise InvalidStatementError, "#{label} is invalid."
      end

      def validate_relationship!
        return if @hotel_corporate_account.hotel_id == @hotel.id

        raise ActiveRecord::RecordNotFound
      end

      def validate_period!
        raise InvalidStatementError, "Start date must be on or before end date." if @start_date > @end_date
        return if @end_date <= business_date

        raise InvalidStatementError, "End date cannot be after the current business date."
      end

      def validate_currency!
        return if @requested_currency.blank? || available_currencies.include?(@requested_currency)

        raise InvalidStatementError, "Currency is not available for this corporate account."
      end

      def business_date
        @business_date ||= (@hotel.current_business_date || @hotel.business_date_for(Time.current)).to_date
      end

      def corporate_account
        @hotel_corporate_account.corporate_account
      end

      def contact_email
        corporate_account.users.min_by(&:id)&.email
      end

      def available_currencies
        @available_currencies ||= begin
          currencies = invoice_scope.distinct.pluck(:currency) + payment_scope.distinct.pluck(:currency)
          currencies << @hotel_corporate_account.credit_currency
          currencies.compact.map(&:to_s).reject(&:blank?).uniq.sort
        end
      end

      def selected_currency
        @selected_currency ||= begin
          return @requested_currency if @requested_currency.present?

          credit_currency = @hotel_corporate_account.credit_currency.to_s
          activity_currencies = available_currencies_with_activity
          activity_currencies.include?(credit_currency) ? credit_currency : activity_currencies.first || credit_currency
        end
      end

      def available_currencies_with_activity
        @available_currencies_with_activity ||= begin
          currencies = invoice_scope.distinct.pluck(:currency) + payment_scope.distinct.pluck(:currency)
          currencies.compact.map(&:to_s).reject(&:blank?).uniq.sort
        end
      end

      def invoice_scope
        @invoice_scope ||= @hotel.ar_invoices
          .where(hotel_corporate_account: @hotel_corporate_account)
          .where.not(status: "void")
      end

      def payment_scope
        @payment_scope ||= @hotel.ar_payments.where(hotel_corporate_account: @hotel_corporate_account)
      end

      def invoices
        @invoices ||= invoice_scope
          .where(currency: selected_currency)
          .where(issued_on: ..@end_date)
          .includes(invoice_includes, ar_payment_allocations: [ :ar_payment, :reversal ])
          .to_a
      end

      def invoice_includes
        return [ :invoice, { booking_folio: [ :booking, { booking_billing_party: :billing_terms } ] } ] unless @include_invoice_details

        [
          :invoice,
          {
            booking_folio: [
              :folio_transactions,
              { booking: { booking_rooms: :room_type } },
              { booking_room: :room_type },
              { booking_billing_party: :billing_terms }
            ]
          }
        ]
      end

      def payments
        @payments ||= payment_scope
          .where(currency: selected_currency)
          .where(received_at: ..@end_date)
          .includes(ar_payment_allocations: [ :ar_invoice, :reversal ])
          .to_a
      end

      def opening_balance
        @opening_balance ||= begin
          debits = invoices.select { |invoice| invoice.issued_on < @start_date }.sum { |invoice| invoice.amount.to_d }
          credits = payments.select { |payment| payment.received_at < @start_date }.sum { |payment| payment.amount.to_d }
          debits - credits
        end
      end

      def period_invoices
        @period_invoices ||= invoices.select { |invoice| invoice.issued_on.between?(@start_date, @end_date) }
      end

      def period_payments
        @period_payments ||= payments.select { |payment| payment.received_at.between?(@start_date, @end_date) }
      end

      def period_invoice_total
        @period_invoice_total ||= period_invoices.sum { |invoice| invoice.amount.to_d }
      end

      def period_payment_total
        @period_payment_total ||= period_payments.sum { |payment| payment.amount.to_d }
      end

      def closing_balance
        @closing_balance ||= opening_balance + period_invoice_total - period_payment_total
      end

      def ledger
        @ledger ||= Ledger.new(ledger_activities, method(:materialize_ledger_row))
      end

      def ledger_activities
        @ledger_activities ||= begin
          balance = opening_balance
          activities = period_invoices.map { |invoice| invoice_activity(invoice) } +
            period_payments.map { |payment| payment_activity(payment) }

          activities.sort_by { |activity| activity.fetch(:sort_key) }.map do |activity|
            balance += activity.fetch(:debit) - activity.fetch(:credit)
            LedgerActivity.new(**activity, balance: balance)
          end
        end
      end

      def invoice_activity(invoice)
        {
          effective_date: invoice.issued_on,
          record_type: "Invoice",
          source: invoice,
          due_on: invoice.due_on,
          debit: invoice.amount.to_d,
          credit: 0.to_d,
          sort_key: [ invoice.issued_on, invoice.created_at, 0, invoice.id ]
        }
      end

      def payment_activity(payment)
        {
          effective_date: payment.received_at,
          record_type: "Payment",
          source: payment,
          due_on: nil,
          debit: 0.to_d,
          credit: payment.amount.to_d,
          sort_key: [ payment.received_at, payment.created_at, 1, payment.id ]
        }
      end

      def materialize_ledger_row(activity)
        source = activity.source
        LedgerRow.new(
          effective_date: activity.effective_date,
          record_type: activity.record_type,
          reference: source.is_a?(ArInvoice) ? source.formatted_invoice_number : source.reference_number,
          description: source.is_a?(ArInvoice) ? invoice_description(source) : payment_description(source),
          due_on: activity.due_on,
          debit: activity.debit,
          credit: activity.credit,
          balance: activity.balance
        )
      end

      def invoice_description(invoice)
        booking = invoice.booking
        terms = billing_terms_for(invoice)
        parts = [ corporate_account.name ]
        parts << "Booking #{booking.confirmation_token}" if booking&.confirmation_token.present?
        parts << "Folio #{invoice.booking_folio.folio_reference_display}" if invoice.booking_folio.present?
        parts << "PO: #{terms.purchase_order_reference}" if terms&.purchase_order_reference.present?
        parts << "Auth: #{terms.authorization_reference}" if terms&.authorization_reference.present?
        parts.join(" · ")
      end

      def billing_terms_for(invoice)
        invoice.booking_folio&.booking_billing_party&.billing_terms
      end

      def payment_description(payment)
        allocations = active_allocations_as_of(payment.ar_payment_allocations, @end_date)
        allocated_total = allocations.sum { |allocation| allocation.amount.to_d }
        allocation_text = allocations.sort_by { |allocation| [ allocation.ar_invoice.invoice_number, allocation.id ] }.map do |allocation|
          "#{allocation.ar_invoice.formatted_invoice_number} #{format_amount(allocation.amount)}"
        end

        parts = [ payment.payment_method.to_s.humanize ]
        parts << "Applied: #{allocation_text.join(', ')}" if allocation_text.any?
        parts << "Unapplied: #{selected_currency} #{format_amount(payment.amount.to_d - allocated_total)}"
        parts.join(" · ")
      end

      def active_allocations_as_of(allocations, date)
        allocations.select do |allocation|
          timestamp_date(allocation.created_at) <= date &&
            allocation.ar_payment.received_at <= date &&
            (allocation.reversal.blank? || timestamp_date(allocation.reversal.reversed_at) > date)
        end
      end

      def unapplied_credit
        @unapplied_credit ||= payments.sum do |payment|
          allocated = active_allocations_as_of(payment.ar_payment_allocations, @end_date)
            .sum { |allocation| allocation.amount.to_d }
          payment.amount.to_d - allocated
        end
      end

      def aging_totals
        @aging_totals ||= begin
          totals = empty_aging
          invoices.each do |invoice|
            balance = invoice_balance_as_of(invoice)
            next unless balance.positive?

            totals[bucket_for(invoice)] += balance
          end
          AgingTotals.new(**totals)
        end
      end

      def invoice_balance_as_of(invoice)
        allocated = active_allocations_as_of(invoice.ar_payment_allocations, @end_date)
          .sum { |allocation| allocation.amount.to_d }
        [ invoice.amount.to_d - allocated, 0.to_d ].max
      end

      def bucket_for(invoice)
        days_overdue = (@end_date - invoice.due_on).to_i
        return :current if days_overdue <= 0
        return :days_1_30 if days_overdue <= 30
        return :days_31_60 if days_overdue <= 60
        return :days_61_90 if days_overdue <= 90

        :days_over_90
      end

      def empty_aging
        {
          current: 0.to_d,
          days_1_30: 0.to_d,
          days_31_60: 0.to_d,
          days_61_90: 0.to_d,
          days_over_90: 0.to_d
        }
      end

      def invoice_details
        @invoice_details ||= begin
          return [] unless @include_invoice_details

          period_invoices
            .sort_by { |invoice| [ invoice.issued_on, invoice.invoice_number ] }
            .map { |invoice| build_invoice_detail(invoice) }
        end
      end

      def build_invoice_detail(invoice)
        folio = invoice.booking_folio
        booking = folio&.booking
        line_items = folio_line_items(folio)

        InvoiceDetail.new(
          invoice: invoice,
          billing_name: booking&.guest_name.presence || folio&.display_name,
          bill_no: invoice.formatted_invoice_number,
          check_in: booking&.check_in,
          check_out: booking&.check_out,
          room_label: room_label_for(folio, booking),
          balance: line_items.last&.balance || 0.to_d,
          line_items: line_items
        )
      end

      def folio_line_items(folio)
        return [] if folio.blank?

        balance = 0.to_d
        folio.folio_transactions.sort_by { |transaction| [ transaction.posting_date, transaction.created_at, transaction.id ] }.map do |transaction|
          charge, credit = transaction_amounts(transaction)
          balance += charge - credit
          LineItem.new(date: transaction.posting_date, description: transaction_description(transaction), charge: charge, credit: credit, balance: balance)
        end
      end

      def transaction_amounts(transaction)
        amount = transaction.amount.to_d
        if transaction.payment?
          amount.negative? ? [ amount.abs, 0.to_d ] : [ 0.to_d, amount.abs ]
        else
          amount.negative? ? [ 0.to_d, amount.abs ] : [ amount.abs, 0.to_d ]
        end
      end

      def transaction_description(transaction)
        return "Reversal - #{transaction.description}" if transaction.reversal_of_transaction_id.present?
        return "Refund - #{transaction.description}" if transaction.category == "refund"
        return "Payment - #{transaction.description}" if transaction.payment?

        transaction.description.to_s
      end

      def room_label_for(folio, booking)
        return "-" if booking.blank?

        rooms = if folio&.booking_room.present?
          [ folio.booking_room ]
        else
          booking.booking_rooms
        end

        labels = rooms.map { |room| room_label(room) }.compact
        labels.presence&.join(", ") || "-"
      end

      def room_label(room)
        type_name = room.room_type_snapshot.to_h["name"].presence || room.room_type&.name
        [ room.room_number.presence, type_name ].compact.join(" - ").presence
      end

      def notes
        [
          "This statement credits payments on their received date. Allocations are informational and do not change the account balance.",
          "Unapplied payments are shown separately from invoice aging.",
          "Historical statements are restated using each invoice's current void status."
        ]
      end

      def format_amount(amount)
        HotelPortal::Reports::Exports::PdfTheme.money(amount)
      end

      def timestamp_date(timestamp)
        timestamp.in_time_zone(@hotel.hotel_time_zone).to_date
      end
    end
  end
end
