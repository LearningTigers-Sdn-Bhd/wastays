# frozen_string_literal: true

module HotelPortal
  class BookingFinancialPresenter
    include ActionView::Helpers::NumberHelper

    STATUS_PRESENTATION = {
      "pending" => { label: "Pending", variant: :neutral },
      "confirmed" => { label: "Confirmed", variant: :info },
      "no_show_detected" => { label: "No-show detected", variant: :warning },
      "checked_in" => { label: "In house", variant: :success },
      "due_out_detected" => { label: "Due-out detected", variant: :warning },
      "checkout_required" => { label: "Checkout due", variant: :warning },
      "cancelled" => { label: "Cancelled", variant: :destructive },
      "completed" => { label: "Checked out", variant: :neutral },
      "overbooked" => { label: "Overbooked", variant: :destructive },
      "no_show" => { label: "No-show", variant: :destructive },
      "voided" => { label: "Voided", variant: :destructive }
    }.freeze

    attr_reader :booking

    def initialize(booking)
      @booking = booking
    end

    def confirmation_token
      @booking.confirmation_token
    end

    def booking_number
      @booking.formatted_reservation_number
    end

    def guest_name
      @booking.guest_name
    end

    def status
      @booking.status
    end

    def status_label
      status_presentation.fetch(:label)
    end

    def status_badge_variant
      status_presentation.fetch(:variant)
    end

    def total_amount
      format_currency(@booking.total_amount)
    end

    def tax_total
      format_currency(@booking.tax_total || 0)
    end

    def margin_amount
      format_currency(@booking.margin_amount || 0)
    end

    def net_amount
      format_currency(@booking.net_amount || 0)
    end

    def formatted_created_at
      @booking.created_at.strftime("%d %b %Y")
    end

    private

    def status_presentation
      STATUS_PRESENTATION.fetch(status) { { label: status.to_s.humanize, variant: :neutral } }
    end

    def format_currency(amount)
      "#{@booking.currency} #{format_money(amount)}"
    end

    def format_money(amount)
      number_with_delimiter(number_with_precision(amount, precision: 2))
    end
  end
end
