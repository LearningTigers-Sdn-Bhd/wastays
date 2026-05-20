# frozen_string_literal: true

require "ostruct"

module Folios
  class CloseForCheckout
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

        balance = folio.outstanding_balance.to_d
        return failure("Cannot check out with outstanding balance of #{formatted_balance(balance)}.", folio: folio, balance: balance) if balance.positive?
        return failure("Cannot check out with credit balance of #{formatted_balance(balance)}. Process refund or adjustment first.", folio: folio, balance: balance) if balance.negative?

        invoice_num = HotelCounter.increment!(hotel: folio.hotel, type: "invoice")
        folio.update!(status: "closed", invoice_number: invoice_num)
        success(folio: folio, balance: balance)
      end
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def formatted_balance(balance)
      "#{@booking.currency.presence || 'MYR'} #{format('%.2f', balance)}"
    end

    def success(folio:, balance: 0.to_d)
      OpenStruct.new(success?: true, folio: folio, balance: balance)
    end

    def failure(error, folio: nil, balance: nil)
      OpenStruct.new(success?: false, error: error, folio: folio, balance: balance)
    end
  end
end
