# frozen_string_literal: true

module HotelPortal
  class BookingFinancialPresenter
    include ActionView::Helpers::NumberHelper

    attr_reader :booking

    def initialize(booking)
      @booking = booking
    end

    def confirmation_token
      @booking.confirmation_token
    end

    def guest_name
      @booking.guest_name
    end

    def status
      @booking.status
    end

    def total_amount
      format_money(@booking.total_amount)
    end

    def tax_total
      format_money(@booking.tax_total || 0)
    end

    def margin_amount
      format_money(@booking.margin_amount || 0)
    end

    def net_amount
      format_money(@booking.net_amount || 0)
    end

    def formatted_created_at
      @booking.created_at.strftime("%d %b %Y")
    end

    private

    def format_money(amount)
      number_with_precision(amount, precision: 2)
    end
  end
end
