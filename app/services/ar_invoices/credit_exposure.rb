# frozen_string_literal: true

module ArInvoices
  class CreditExposure
    WARNING_THRESHOLD = 90.to_d

    Result = Struct.new(
      :hotel_corporate_account,
      :current_outstanding,
      :pending_amount,
      :projected_exposure,
      :credit_limit,
      :credit_currency,
      :usage_percentage,
      :warning_state,
      :warning_message,
      keyword_init: true
    ) do
      def warning?
        warning_state != "none"
      end

      def over_limit?
        warning_state == "over_limit"
      end

      def near_limit?
        warning_state == "near_limit"
      end
    end

    def self.call(hotel_corporate_account:, pending_amount: 0, pending_currency: nil)
      new(
        hotel_corporate_account: hotel_corporate_account,
        pending_amount: pending_amount,
        pending_currency: pending_currency
      ).call
    end

    def initialize(hotel_corporate_account:, pending_amount: 0, pending_currency: nil)
      @hotel_corporate_account = hotel_corporate_account
      @pending_amount = pending_amount.to_d
      @pending_currency = pending_currency.presence
    end

    def call
      Result.new(
        hotel_corporate_account: @hotel_corporate_account,
        current_outstanding: current_outstanding,
        pending_amount: comparable_pending_amount,
        projected_exposure: projected_exposure,
        credit_limit: credit_limit,
        credit_currency: credit_currency,
        usage_percentage: usage_percentage,
        warning_state: warning_state,
        warning_message: warning_message
      )
    end

    private

    def current_outstanding
      @current_outstanding ||= @hotel_corporate_account.ar_invoices
        .with_open_balance
        .where(currency: credit_currency)
        .sum(:outstanding_amount)
        .to_d
    end

    def projected_exposure
      current_outstanding + comparable_pending_amount
    end

    def credit_limit
      @credit_limit ||= @hotel_corporate_account.credit_limit&.to_d
    end

    def credit_currency
      @hotel_corporate_account.credit_currency.presence || @hotel_corporate_account.hotel.default_currency.presence || "MYR"
    end

    def comparable_pending_amount
      return @pending_amount if @pending_currency.blank? || @pending_currency == credit_currency

      0.to_d
    end

    def usage_percentage
      return nil if credit_limit.blank? || credit_limit.zero?

      ((projected_exposure / credit_limit) * 100).round(2)
    end

    def warning_state
      return "no_limit" if credit_limit.blank?
      return "over_limit" if projected_exposure > credit_limit
      return "near_limit" if usage_percentage.present? && usage_percentage >= WARNING_THRESHOLD

      "none"
    end

    def warning_message
      case warning_state
      when "no_limit"
        "No credit limit is set for this corporate account. Direct Bill is still allowed."
      when "near_limit"
        "Projected AR exposure #{money(projected_exposure)} is #{usage_percentage.to_i}% of credit limit #{money(credit_limit)}. Direct Bill is still allowed."
      when "over_limit"
        "Projected AR exposure #{money(projected_exposure)} exceeds credit limit #{money(credit_limit)}. Direct Bill is still allowed."
      end
    end

    def money(amount)
      "#{credit_currency} #{format('%.2f', amount.to_d)}"
    end
  end
end
