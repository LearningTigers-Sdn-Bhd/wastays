# frozen_string_literal: true

module Invoices
  class Snapshot
    def self.call(folio:)
      new(folio:).call
    end

    def initialize(folio:)
      @folio = folio
      @booking = folio.booking
      @hotel = folio.hotel
    end

    def call
      {
        hotel: hotel_snapshot,
        booking: booking_snapshot,
        folio: folio_snapshot,
        payer: payer_snapshot,
        rooms: room_snapshots,
        transactions: transaction_snapshots,
        totals: totals_snapshot
      }
    end

    private

    def hotel_snapshot
      {
        id: @hotel.id,
        name: @hotel.name,
        address: @hotel.address,
        city: @hotel.city,
        country: @hotel.country,
        contact_phone: @hotel.contact_phone,
        contact_email: @hotel.contact_email,
        time_zone: @hotel.hotel_time_zone.name
      }
    end

    def booking_snapshot
      {
        id: @booking.id,
        confirmation_token: @booking.confirmation_token,
        reservation_reference: @booking.formatted_reservation_number,
        guest_name: @booking.guest_name,
        guest_country: @booking.guest_country,
        check_in: @booking.check_in&.iso8601,
        check_out: @booking.check_out&.iso8601
      }
    end

    def folio_snapshot
      {
        id: @folio.id,
        folio_reference: @folio.folio_reference_display,
        folio_account_reference: @folio.account_reference,
        label: @folio.label,
        folio_type: @folio.folio_type,
        payer_type: @folio.payer_type,
        currency: @folio.currency,
        status: @folio.status,
        closed_at: @folio.closed_at&.iso8601
      }
    end

    def payer_snapshot
      party = @folio.booking_billing_party
      relationship = @folio.hotel_corporate_account || party&.hotel_corporate_account
      terms = party&.billing_terms

      {
        type: @folio.payer_type,
        name: party&.display_name.presence || relationship&.corporate_account&.name.presence || @booking.guest_name,
        account_type: party&.account_type.presence || relationship&.account_type,
        hotel_corporate_account_id: relationship&.id,
        corporate_account_id: relationship&.corporate_account_id,
        settlement_type: terms&.settlement_type,
        purchase_order_reference: terms&.purchase_order_reference,
        authorization_reference: terms&.authorization_reference,
        payment_terms_days: relationship&.payment_terms_days
      }
    end

    def room_snapshots
      rooms = @folio.booking_room.present? ? [ @folio.booking_room ] : @booking.booking_rooms.includes(:room_type).to_a
      rooms.map do |room|
        {
          id: room.id,
          room_number: room.room_number,
          room_type: room.room_type_snapshot.to_h["name"].presence || room.room_type&.name
        }
      end
    end

    def transaction_snapshots
      transactions.map do |transaction|
        {
          id: transaction.id,
          transaction_type: transaction.transaction_type,
          category: transaction.category,
          code: transaction.posted_transaction_code,
          code_name: transaction.posted_transaction_code_name,
          description: transaction.description,
          amount: decimal(transaction.amount),
          currency: transaction.currency,
          posting_date: transaction.posting_date&.iso8601,
          created_at: transaction.created_at&.iso8601,
          user_name: transaction.user&.name,
          reversal_of_transaction_id: transaction.reversal_of_transaction_id,
          voided_by_transaction_id: transaction.voided_by_transaction_id,
          metadata: transaction.metadata.to_h
        }
      end
    end

    def totals_snapshot
      charges = transactions.select(&:charge?).sum { |transaction| transaction.amount.to_d }
      payments = transactions.select(&:payment?).sum { |transaction| transaction.amount.to_d }
      adjustments = transactions.select(&:adjustment?).sum { |transaction| transaction.amount.to_d }

      {
        charges: decimal(charges),
        payments: decimal(payments),
        adjustments: decimal(adjustments),
        balance: decimal(charges - payments + adjustments),
        currency: @folio.currency
      }
    end

    def transactions
      @transactions ||= @folio.folio_transactions
        .includes(:transaction_code, :user)
        .order(:posting_date, :created_at, :id)
        .to_a
    end

    def decimal(value)
      value.to_d.to_s("F")
    end
  end
end
