# frozen_string_literal: true

require "ostruct"

module Folios
  class CloseFolio
    PERMISSION = "manage_folio_windows"

    DIRECT_BILL_SETTLEMENT = "direct_bill"

    def self.call(folio:, user:, reason: nil, settlement_method: nil)
      new(folio: folio, user: user, reason: reason, settlement_method: settlement_method).call
    end

    def initialize(folio:, user:, reason: nil, settlement_method: nil)
      @folio = folio
      @booking = folio.booking
      @hotel = folio.hotel
      @user = user
      @reason = reason.to_s.strip.presence
      @settlement_method = settlement_method.to_s
    end

    def call
      return failure("You do not have permission to manage folio windows.") unless permitted?

      @folio.with_lock do
        @folio.reload
        return failure("Folio is already closed.") if @folio.closed?
        return failure("Voided folios cannot be closed.") if @folio.voided?
        return failure("Cannot close a folio with pending upcoming charges.") if @folio.projected_forecasts.exists?

        balance = @folio.outstanding_balance.to_d
        direct_bill = direct_bill_settlement?
        validation_error = direct_bill ? validate_direct_bill_close(balance) : validate_standard_close(balance)
        return failure(validation_error) if validation_error.present?

        @folio.update!(status: "closed", closed_at: Time.current, closed_by: @user)
        ar_invoice = create_ar_invoice!(balance) if direct_bill
        FolioOperationLog.create!(
          hotel: @hotel,
          booking: @booking,
          actor: @user,
          operation_type: "close_folio",
          source_folio: @folio,
          target_folio: @folio,
          amount: balance,
          currency: @folio.currency,
          reason: @reason,
          metadata: close_metadata(ar_invoice)
        )
        record_direct_bill_audit_event!(ar_invoice, balance) if direct_bill
      end

      success(@folio)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def direct_bill_settlement?
      @settlement_method == DIRECT_BILL_SETTLEMENT
    end

    def validate_standard_close(balance)
      return if balance.zero?

      "Cannot close folio with non-zero balance of #{formatted_balance(balance)}."
    end

    def validate_direct_bill_close(balance)
      return "Direct Bill settlement is only available for Company & Government folios." unless @folio.payer_type == "company"
      return "Direct Bill settlement requires a Company & Government Account." if hotel_corporate_account.blank?
      return "Company & Government Account must be active for Direct Bill settlement." unless hotel_corporate_account.active?
      return "Direct Bill is not enabled for this Company & Government Account." unless hotel_corporate_account.direct_bill_enabled?
      return "Direct Bill settlement requires a positive folio balance." unless balance.positive?
      "AR invoice already exists for this folio." if @folio.ar_invoice.present?
    end

    def create_ar_invoice!(balance)
      Folios::CreateDirectBillArInvoice.call!(folio: @folio, balance: balance)
    end

    def close_metadata(ar_invoice)
      metadata = { closed_at: @folio.closed_at&.iso8601 }
      return metadata if ar_invoice.blank?

      metadata.merge(
        settlement_method: DIRECT_BILL_SETTLEMENT,
        ar_invoice_id: ar_invoice.id,
        ar_invoice_number: ar_invoice.invoice_number,
        due_on: ar_invoice.due_on.iso8601
      )
    end

    def record_direct_bill_audit_event!(ar_invoice, balance)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: @hotel.current_business_date,
        event_type: "direct_bill_folio_closed",
        source: "folio_window",
        actor: @user,
        booking_folio: @folio,
        booking: @booking,
        amount: balance,
        currency: @folio.currency,
        metadata: {
          ar_invoice_id: ar_invoice.id,
          ar_invoice_number: ar_invoice.invoice_number,
          hotel_corporate_account_id: hotel_corporate_account.id,
          corporate_account_id: hotel_corporate_account.corporate_account_id,
          due_on: ar_invoice.due_on.iso8601,
          settlement_method: DIRECT_BILL_SETTLEMENT
        }
      )
    end

    def hotel_corporate_account
      @hotel_corporate_account ||= @folio.hotel_corporate_account
    end

    def formatted_balance(balance)
      "#{@folio.currency} #{format('%.2f', balance)}"
    end

    def permitted?
      @user&.respond_to?(:superadmin?) && @user.superadmin? ||
        @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
    end

    def success(folio)
      OpenStruct.new(success?: true, folio: folio)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, folio: @folio)
    end
  end
end
