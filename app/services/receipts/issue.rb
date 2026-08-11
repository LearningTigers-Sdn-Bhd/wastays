# frozen_string_literal: true

module Receipts
  class Issue
    def self.call!(source:)
      new(source).call!
    end

    def initialize(source)
      @source = source
    end

    def call!
      existing = existing_receipt
      return existing if existing
      return unless receiptable?

      allocation = DocumentIdentifiers::Issuer.issue!(hotel:, type: :receipt)
      Receipt.create!(attributes(allocation))
    rescue ActiveRecord::RecordNotUnique
      existing_receipt || raise
    end

    private

    def receiptable?
      return @source.status.in?(%w[held available settled]) if @source.is_a?(Deposit)
      return true unless @source.is_a?(FolioTransaction)

      metadata = @source.metadata.to_h
      return false if metadata["receipt_policy"].to_s == "none" || metadata[:receipt_policy].to_s == "none"
      return false if metadata["posting_source"].to_s == "ota_credit" || metadata[:posting_source].to_s == "ota_credit"

      @source.payment? && @source.amount.positive? && @source.category != "refund" && metadata["deposit_id"].blank? && metadata[:deposit_id].blank?
    end

    def attributes(allocation)
      {
        hotel:,
        receipt_number: allocation.number,
        receipt_year: allocation.year,
        public_number: allocation.reference,
        amount: @source.amount,
        currency: @source.currency,
        payment_method: payment_method,
        external_reference: external_reference,
        received_at: received_at,
        issued_at: Time.current,
        payer_snapshot: payer_snapshot,
        context_snapshot: context_snapshot,
        metadata: {},
        **source_reference,
        payment_transaction: payment_transaction
      }
    end

    def hotel
      @hotel ||= @source.hotel
    end

    def payment_method
      return @source.payment_method if @source.respond_to?(:payment_method) && @source.payment_method.present?
      return payment_transaction.payment_method if payment_transaction&.payment_method.present?

      @source.is_a?(FolioTransaction) ? @source.category : "other"
    end

    def external_reference
      return @source.external_reference if @source.respond_to?(:external_reference)
      return @source.reference_number if @source.respond_to?(:reference_number)

      payment_transaction&.external_reference
    end

    def received_at
      return @source.received_at if @source.respond_to?(:received_at) && @source.received_at.present?
      return @source.posted_at if @source.respond_to?(:posted_at) && @source.posted_at.present?
      return @source.posting_date.in_time_zone if @source.respond_to?(:posting_date) && @source.posting_date.present?

      Time.current
    end

    def payment_transaction
      return unless @source.is_a?(FolioTransaction)

      id = @source.metadata.to_h["payment_transaction_id"]
      transaction = PaymentTransaction.find_by(id:) if id.present?
      transaction if transaction && payment_transaction_hotel_id(transaction) == hotel.id
    end

    def payment_transaction_hotel_id(transaction)
      transaction.booking&.hotel_id ||
        transaction.ar_payment&.hotel_id ||
        transaction.corporate_ar_payment_intent&.hotel_id ||
        transaction.booking_quote&.hotel_id
    end

    def payer_snapshot
      booking = source_booking
      guest = @source.group_booking&.organizer_guest if @source.is_a?(Deposit) && @source.group_booking.present?
      {
        name: booking&.guest_name || guest&.name,
        email: booking&.guest_email || guest&.email,
        phone: booking&.guest_phone || guest&.phone
      }.compact
    end

    def context_snapshot
      booking = source_booking
      group = @source.respond_to?(:group_booking) ? @source.group_booking : booking&.group_booking
      {
        booking_id: booking&.id,
        booking_confirmation_token: booking&.confirmation_token,
        group_booking_id: group&.id,
        group_confirmation_token: group&.confirmation_token
      }.compact
    end

    def source_booking
      return @source.booking_folio.booking if @source.is_a?(FolioTransaction)
      @source.booking if @source.respond_to?(:booking)
    end

    def source_reference
      case @source
      when FolioTransaction then { folio_transaction: @source }
      when Deposit then { deposit: @source }
      when ArPayment then { ar_payment: @source }
      else raise ArgumentError, "Unsupported receipt source: #{@source.class.name}"
      end
    end

    def existing_receipt
      Receipt.find_by(source_reference)
    end
  end
end
