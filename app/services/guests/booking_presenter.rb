# frozen_string_literal: true

module Guests
  class BookingPresenter
    attr_reader :booking

    delegate :id, :confirmation_token, :status, :currency, :total_amount, :tourism_tax?, :tourism_tax_amount, :pre_checkin_status, to: :booking

    def initialize(booking)
      @booking = booking
    end

    def check_in_formatted
      helpers.format_date(booking.check_in)
    end

    def check_out_formatted
      helpers.format_date(booking.check_out)
    end

    def nights_count
      (booking.check_out.to_date - booking.check_in.to_date).to_i
    end

    def nights_label
      "#{nights_count} #{'night'.pluralize(nights_count)}"
    end

    def status_humanized
      booking.status.humanize
    end

    def formatted_total_amount
      prefix = (currency == "USD" ? "USD" : "RM")
      "#{prefix} #{helpers.number_with_precision(total_amount, precision: 2, delimiter: ",")}"
    end

    def formatted_tourism_tax_amount
      "Tax RM #{helpers.number_with_precision(tourism_tax_amount, precision: 2, delimiter: ",")}"
    end

    def created_at_time_formatted
      booking.created_at.strftime("%I:%M %p")
    end

    def created_at_date_formatted
      helpers.format_date(booking.created_at)
    end

    def pre_checkin_status_label
      pre_checkin_status&.humanize || "Pending"
    end

    private

    def helpers
      @helpers ||= begin
        h = ApplicationController.helpers
        h.extend(ApplicationHelper) unless h.respond_to?(:format_date)
        h
      end
    end
  end
end
