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
        @balance = balance || folio.outstanding_balance.to_d
      end

      def call!
        issued_on = @hotel.current_business_date
        terms_days = @hotel_corporate_account.payment_terms_days.to_i
        ArInvoice.create!(
          hotel: @hotel,
          booking_folio: @folio,
          hotel_corporate_account: @hotel_corporate_account,
          invoice_number: invoice_allocation.number,
          invoice_year: invoice_allocation.year,
          invoice_reference: invoice_allocation.reference,
          status: "open",
          amount: @balance,
          paid_amount: 0,
          outstanding_amount: @balance,
          currency: @folio.currency,
          issued_on: issued_on,
          due_on: issued_on + terms_days.days,
          metadata: metadata(terms_days)
        )
      end

      private

      def invoice_allocation
        @invoice_allocation ||= DocumentIdentifiers::Issuer.issue!(hotel: @hotel, type: :ar_invoice)
      end

      def metadata(terms_days)
        {
          booking_id: @booking.id,
          corporate_account_id: @hotel_corporate_account.corporate_account_id,
          corporate_account_name: @hotel_corporate_account.corporate_account&.name,
          hotel_corporate_account_id: @hotel_corporate_account.id,
          payment_terms_days: terms_days,
          folio_balance: @balance.to_s("F"),
          direct_bill_closed_at: Time.current.iso8601
        }
      end
    end
  end
end
