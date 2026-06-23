# frozen_string_literal: true

require "ostruct"

module Folios
  class CloseForCheckout
    def self.call(booking:, user:, checked_out_at: Time.current, options: {})
      new(booking: booking, user: user, checked_out_at: checked_out_at, options: options).call
    end

    def initialize(booking:, user:, checked_out_at: Time.current, options: {})
      @booking = booking
      @user = user
      @checked_out_at = checked_out_at
      @options = options
    end

    def call
      folios = @booking.booking_folios.includes(:folio_forecasted_charges, :folio_transactions).to_a
      return failure("Booking has no folio.") if folios.empty?
      primary_folio = @booking.booking_folio || folios.first

      @booking.with_lock do
        folios.each(&:lock!)
        folios.each(&:reload)
        if folios.any?(&:closed?)
          message = folios.one? ? "Folio is already closed." : "One or more folios are already closed."
          return failure(message, folio: primary_folio)
        end
        return failure("Voided folios cannot be checked out.", folio: primary_folio) if folios.any?(&:voided?)

        posting_guard_error = validate_checkout_business_date(primary_folio)
        return failure(posting_guard_error, folio: primary_folio) if posting_guard_error.present?

        sync_error = sync_payment_and_refund_state(primary_folio)
        return failure(sync_error, folio: primary_folio) if sync_error.present?

        folios.each { |folio| Folios::SyncForecastedCharges.call(booking_folio: folio) }
        folios.each(&:reload)

        missing_charges_error = validate_all_nights_posted(folios)
        return failure(missing_charges_error, folio: primary_folio) if missing_charges_error.present?

        balance = folios.sum { |folio| calculate_fresh_balance(folio) }
        return failure("Cannot check out with outstanding balance of #{formatted_balance(balance)}.", folio: primary_folio, balance: balance) if balance.positive?
        return failure("Cannot check out with credit balance of #{formatted_balance(balance)}. Process refund or adjustment first.", folio: primary_folio, balance: balance) if balance.negative?

        invoice_num = HotelCounter.increment!(hotel: primary_folio.hotel, type: "invoice")
        folios.each do |folio|
          attributes = { status: "closed", closed_at: Time.current, closed_by: @user }
          attributes[:invoice_number] = invoice_num if folio.id == primary_folio.id
          folio.update!(attributes)
          record_financial_audit_event!(folio, calculate_fresh_balance(folio))
        end
        success(folio: primary_folio.reload, balance: balance)
      end
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validate_checkout_business_date(folio)
      business_date = folio.hotel.current_business_date
      FinancialControls::PostingGuard.call!(
        hotel: folio.hotel,
        business_date: business_date,
        actor: @user,
        posting_source: @options[:posting_source].presence || "checkout",
        override: @options[:override_night_audit],
        override_reason: @options[:correction_reason],
        permission_context: @options[:permission_context] || @user,
        blocker_resolution: @options[:blocker_resolution],
        system_posting: !!@options[:system_posting]
      )
      nil
    rescue FinancialControls::PostingGuard::PostingBlocked => e
      e.message
    end

    def validate_all_nights_posted(folios)
      checkout_date = @booking.check_out.to_date
      unsettled = FolioForecastedCharge.where(booking_folio_id: folios.map(&:id)).forecast
        .where(arel_table[:stay_date].lt(checkout_date))
      return if unsettled.none?

      dates = unsettled.pluck(:stay_date).uniq.sort
      "Missing nightly charges for: #{dates.map { |d| d.strftime('%d %b') }.join(', ')}. Please ensure all nightly charges are posted before checkout."
    end

    def arel_table
      FolioForecastedCharge.arel_table
    end

    def calculate_fresh_balance(folio)
      charges = FolioTransaction.charge.where(booking_folio_id: folio.id).sum(:amount)
      payments = FolioTransaction.payment.where(booking_folio_id: folio.id).sum(:amount)
      adjustments = FolioTransaction.adjustment.where(booking_folio_id: folio.id).sum(:amount)

      charges.to_d - payments.to_d + adjustments.to_d
    end

    def sync_payment_and_refund_state(folio)
      @booking.payment_transactions.where(status: "captured").find_each do |payment_transaction|
        next if payment_synced?(folio, payment_transaction)

        result = Folios::RecordPaymentFromGateway.call(payment_transaction)
        folio.reload
        next if result&.success? && payment_synced?(folio, payment_transaction)

        return "Cannot check out: captured payment is not synced to the folio."
      end

      refund_request = @booking.refund_request
      if refund_request&.completed? && !refund_synced?(folio, refund_request)
        result = Folios::RecordRefund.call(
          refund_request: refund_request,
          user: @user,
          options: { posting_source: "sync", system_posting: true }
        )
        folio.reload
        unless result&.success? && refund_synced?(folio, refund_request)
          return "Cannot check out: completed refund is not synced to the folio."
        end
      end

      nil
    end

    def payment_synced?(folio, payment_transaction)
      expected_amount = payment_transaction.amount_subunits.to_d / 100.0

      folio.folio_transactions.payment.any? do |transaction|
        transaction.metadata["payment_transaction_id"].to_s == payment_transaction.id.to_s &&
          transaction.amount.to_d == expected_amount
      end
    end

    def refund_synced?(folio, refund_request)
      expected_amount = -refund_request.refund_amount.to_d

      folio.folio_transactions.payment.any? do |transaction|
        transaction.metadata["refund_request_id"].to_s == refund_request.id.to_s &&
          transaction.amount.to_d == expected_amount
      end
    end

    def formatted_balance(balance)
      "#{@booking.currency.presence || 'MYR'} #{format('%.2f', balance)}"
    end

    def record_financial_audit_event!(folio, balance)
      FinancialControls::AuditEventRecorder.call!(
        hotel: folio.hotel,
        business_date: folio.hotel.current_business_date,
        event_type: "folio_closed_for_checkout",
        source: "checkout",
        actor: @user,
        booking_folio: folio,
        booking: @booking,
        amount: balance,
        currency: @booking.currency,
        metadata: {
          invoice_number: folio.invoice_number,
          balance: balance.to_s,
          checked_out_at: checked_out_at_for_metadata
        }
      )
    end

    def checked_out_at_for_metadata
      return @checked_out_at.iso8601 if @checked_out_at.respond_to?(:iso8601)

      @checked_out_at.to_s
    end

    def success(folio:, balance: 0.to_d)
      OpenStruct.new(success?: true, folio: folio, balance: balance)
    end

    def failure(error, folio: nil, balance: nil)
      OpenStruct.new(success?: false, error: error, folio: folio, balance: balance)
    end
  end
end
