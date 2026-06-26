# frozen_string_literal: true

require "ostruct"

module CorporateArPayments
  class CreateIntent
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, hotel_corporate_account_id:, invoice_ids:, amount:, currency:, gateway: nil)
      @user = user
      @hotel_corporate_account_id = hotel_corporate_account_id
      @invoice_ids = Array(invoice_ids).reject(&:blank?).map(&:to_i).uniq
      @amount = amount.to_d
      @currency = currency.to_s
      @gateway = gateway.to_s.presence || "razorpay"
    end

    def call
      error = validate_inputs
      return failure(error) if error.present?

      intent = CorporateArPaymentIntent.create!(
        corporate_account: @user.account,
        user: @user,
        hotel: relationship.hotel,
        hotel_corporate_account: relationship,
        amount: @amount,
        currency: @currency,
        gateway: @gateway,
        expires_at: 30.minutes.from_now,
        invoice_snapshots: invoice_snapshots,
        remittance_suggestions: remittance_suggestions,
        metadata: {
          source: "corporate_portal",
          selected_invoice_ids: invoices.map(&:id)
        }
      )

      success(intent)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validate_inputs
      return "Payment amount must be greater than zero." unless @amount.positive?
      return "Select at least one unpaid invoice." if @invoice_ids.empty?
      return "Only Razorpay is available for corporate AR payments." unless @gateway == "razorpay"
      return "Corporate relationship is not available for payment." if relationship.blank? || !relationship.active?
      return "Currency is not available for this payment." if @currency.blank?
      return "Selected invoices are not available for payment." if invoices.length != @invoice_ids.length
      return "Selected invoices must use one currency." if invoices.map(&:currency).uniq != [ @currency ]

      nil
    end

    def relationship
      @relationship ||= @user.account.hotel_corporate_accounts.includes(:hotel).find_by(id: @hotel_corporate_account_id)
    end

    def invoices
      @invoices ||= begin
        return [] if relationship.blank?

        relationship.hotel.ar_invoices
          .with_open_balance
          .where(hotel_corporate_account: relationship, currency: @currency, id: @invoice_ids)
          .includes(booking_folio: :booking)
          .order(due_on: :asc, invoice_number: :asc)
          .to_a
      end
    end

    def invoice_snapshots
      invoices.map do |invoice|
        {
          ar_invoice_id: invoice.id,
          invoice_number: invoice.invoice_number,
          invoice_label: invoice.formatted_invoice_number,
          hotel_id: invoice.hotel_id,
          hotel_corporate_account_id: invoice.hotel_corporate_account_id,
          currency: invoice.currency,
          amount: invoice.amount.to_s("F"),
          paid_amount: invoice.paid_amount.to_s("F"),
          outstanding_amount: invoice.outstanding_amount.to_s("F"),
          status: invoice.status,
          issued_on: invoice.issued_on.iso8601,
          due_on: invoice.due_on.iso8601,
          booking_confirmation: invoice.booking.confirmation_token
        }
      end
    end

    def remittance_suggestions
      @remittance_suggestions ||= CorporateArPayments::Suggestions.call(invoices: invoices, amount: @amount)
    end

    def success(intent)
      OpenStruct.new(success?: true, intent: intent, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, intent: nil, error: error)
    end
  end
end
