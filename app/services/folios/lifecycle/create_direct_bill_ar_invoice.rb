# frozen_string_literal: true

module Folios
  module Lifecycle
    class CreateDirectBillArInvoice
      def self.call!(folio:, balance: nil)
        new(folio: folio, balance: balance).call!
      end

      def initialize(folio:, balance: nil)
        @folio = folio
        @hotel = folio.hotel
        @booking = folio.booking
        @hotel_corporate_account = folio.hotel_corporate_account
        @balance = balance
      end

      def call!
        @folio.with_lock do
          @folio.reload
          raise ArgumentError, "Direct Bill invoice requires a closed folio." unless @folio.closed?

          if @folio.invoice.present? || @folio.invoice_number.present?
            raise ArgumentError, "Direct Bill folios cannot also have a folio invoice."
          end

          create_invoice!
        end
      end

      private

      def create_invoice!
      balance = (@balance || @folio.outstanding_balance).to_d
      issued_on = @hotel.current_business_date
      terms_days = @hotel_corporate_account.payment_terms_days.to_i
      allocation = invoice_allocation
      issued_at = Time.current
      snapshot = FolioInvoices::Snapshot.call(folio: @folio)
      invoice = Invoice.create!(
        hotel: @hotel,
        booking_folio: @folio,
        kind: "direct_bill",
        invoice_number: allocation.number,
        invoice_year: allocation.year,
        invoice_reference: allocation.reference,
        state: "finalized",
        current_revision_number: 1,
        issued_on:,
        issued_at:
      )
      invoice.revisions.create!(
        hotel: @hotel,
        revision_number: 1,
        document_reference: allocation.reference,
        snapshot:,
        issued_at:
      )
      ArInvoice.create!(
        invoice:,
        hotel: @hotel,
          booking_folio: @folio,
          hotel_corporate_account: @hotel_corporate_account,
        invoice_number: allocation.number,
        invoice_year: allocation.year,
        invoice_reference: allocation.reference,
          status: "open",
          amount: balance,
          paid_amount: 0,
          outstanding_amount: balance,
          currency: @folio.currency,
          issued_on: issued_on,
          due_on: issued_on + terms_days.days,
        metadata: metadata(terms_days, balance, snapshot)
        )
      end

      def invoice_allocation
        @invoice_allocation ||= DocumentIdentifiers::Issuer.issue!(hotel: @hotel, type: :ar_invoice)
      end

      def metadata(terms_days, balance, snapshot)
        {
          booking_id: @booking.id,
          corporate_account_id: @hotel_corporate_account.corporate_account_id,
          corporate_account_name: @hotel_corporate_account.corporate_account&.name,
          hotel_corporate_account_id: @hotel_corporate_account.id,
          payment_terms_days: terms_days,
          folio_balance: balance.to_s("F"),
          direct_bill_closed_at: Time.current.iso8601,
          document_snapshot: snapshot
        }
      end
    end
  end
end
