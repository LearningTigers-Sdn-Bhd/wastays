# frozen_string_literal: true

require "ostruct"

module Folios
  class CloseForCheckout
    include NightlyChargeCalculation

    def self.call(booking:, user:, checked_out_at: Time.current)
      new(booking: booking, user: user, checked_out_at: checked_out_at).call
    end

    def initialize(booking:, user:, checked_out_at: Time.current)
      @booking = booking
      @user = user
      @checked_out_at = checked_out_at
    end

    def call
      folio = @booking.booking_folio
      return failure("Booking has no folio.") unless folio

      folio.with_lock do
        folio.reload
        return failure("Folio is already closed.", folio: folio) if folio.status == "closed"

        posting_guard_error = validate_checkout_business_date(folio)
        return failure(posting_guard_error, folio: folio) if posting_guard_error.present?

        missing_charges_error = validate_all_nights_posted(folio)
        return failure(missing_charges_error, folio: folio) if missing_charges_error.present?

        balance = calculate_fresh_balance(folio)
        return failure("Cannot check out with outstanding balance of #{formatted_balance(balance)}.", folio: folio, balance: balance) if balance.positive?
        return failure("Cannot check out with credit balance of #{formatted_balance(balance)}. Process refund or adjustment first.", folio: folio, balance: balance) if balance.negative?

        invoice_num = HotelCounter.increment!(hotel: folio.hotel, type: "invoice")
        folio.update!(status: "closed", invoice_number: invoice_num)
        record_financial_audit_event!(folio, balance)
        success(folio: folio, balance: balance)
      end
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def validate_checkout_business_date(folio)
      FinancialControls::PostingGuard.call!(
        hotel: folio.hotel,
        business_date: folio.hotel.business_date_for(@checked_out_at),
        actor: @user,
        posting_source: "checkout"
      )
      nil
    rescue FinancialControls::PostingGuard::PostingBlocked => e
      e.message
    end

    def validate_all_nights_posted(folio)
      business_date = folio.hotel.business_date_for(@checked_out_at)
      expected_dates = (@booking.check_in.to_date...business_date).to_a

      return if expected_dates.empty?

      missing_dates = expected_dates.select do |date|
        missing_accommodation_charge?(folio, date) || missing_tax_charge?(folio, date)
      end

      if missing_dates.any?
        "Missing nightly charges for: #{missing_dates.uniq.map { |d| d.strftime('%d %b') }.join(', ')}. Please ensure all nightly charges are posted before checkout."
      end
    end

    def missing_accommodation_charge?(folio, date)
      expected_total = @booking.booking_rooms.to_a.sum { |room| nightly_room_amount(room, date) }
      return false if expected_total.zero?

      posted_charge_total(folio, "accommodation", date) != expected_total
    end

    def missing_tax_charge?(folio, date)
      expected_total = tax_postings_for(@booking, date).sum { |tax_line| tax_line_amount(tax_line) }
      return false unless expected_total.positive?

      posted_charge_total(folio, "tax", date) != expected_total
    end

    def posted_charge_total(folio, category, date)
      FolioTransaction.charge
        .where(booking_folio_id: folio.id)
        .where(category: category)
        .where("metadata->>'stay_date' = ?", date.iso8601)
        .sum(:amount)
        .to_d
    end

    def calculate_fresh_balance(folio)
      charges = FolioTransaction.charge.where(booking_folio_id: folio.id).sum(:amount)
      payments = FolioTransaction.payment.where(booking_folio_id: folio.id).sum(:amount)
      adjustments = FolioTransaction.adjustment.where(booking_folio_id: folio.id).sum(:amount)

      charges.to_d - payments.to_d + adjustments.to_d
    end

    def formatted_balance(balance)
      "#{@booking.currency.presence || 'MYR'} #{format('%.2f', balance)}"
    end

    def record_financial_audit_event!(folio, balance)
      FinancialControls::AuditEventRecorder.call!(
        hotel: folio.hotel,
        business_date: folio.hotel.business_date_for(@checked_out_at),
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
