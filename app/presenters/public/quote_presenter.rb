# frozen_string_literal: true

module Public
  class QuotePresenter < SimpleDelegator
    def initialize(quote, view_context, display_currency = nil)
      @quote = quote
      @view_context = view_context
      @display_currency = display_currency || quote.display_currency
      super(quote)
    end

    def stay_length
      @stay_length ||= (check_out - check_in).to_i
    end

    def stay_length_text
      @view_context.pluralize(stay_length, "night")
    end

    def cancellation_policy
      cancellation_policy_snapshot.presence || "Standard cancellation policy applies. Refund eligibility depends on your check-in date."
    end

    alias_method :cancellation_policy_text, :cancellation_policy

    def formatted_total
      if display_currency.present? && display_total_amount.present?
        CurrencyFormatter.format(display_total_amount, currency: display_currency)
      else
        @view_context.display_amount(total_amount, quote_currency: currency, display_currency: @display_currency, hotel: hotel)
      end
    end

    def formatted_item_subtotal(item)
      @view_context.display_amount(item.subtotal, quote_currency: currency, display_currency: @display_currency, hotel: hotel)
    end

    def formatted_check_in
      check_in.strftime("%a, %b %d")
    end

    alias_method :display_check_in, :formatted_check_in

    def formatted_check_out
      check_out.strftime("%a, %b %d")
    end

    alias_method :display_check_out, :formatted_check_out

    def total_amount_display(display_currency, hotel)
      if display_currency.present? && display_total_amount.present?
        CurrencyFormatter.format(display_total_amount, currency: display_currency)
      else
        @view_context.display_amount(total_amount, quote_currency: currency, display_currency: display_currency, hotel: hotel)
      end
    end

    def public_booking_url
      @view_context.quote_url(token, host: @view_context.request.base_url)
    end
  end
end
