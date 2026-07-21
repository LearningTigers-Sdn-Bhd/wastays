# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class StatementPresenter
      PER_PAGE = 50

      attr_reader :report, :params

      def initialize(report:, params:)
        @report = report
        @params = params
      end

      delegate :corporate_account, :contact_email, :start_date, :end_date, :currency,
        :available_currencies, :opening_balance, :period_invoices, :period_payments,
        :closing_balance, :unapplied_credit, :aging, :notes, to: :report

      def hotel
        report.hotel_corporate_account.hotel
      end

      def paginated_rows
        @paginated_rows ||= Kaminari.paginate_array(report.ledger_rows).page(params[:page]).per(PER_PAGE)
      end

      def pagination_params
        { start_date: start_date.iso8601, end_date: end_date.iso8601, currency: currency }
      end

      def payment_terms
        days = report.hotel_corporate_account.payment_terms_days
        return "Not set" if days.nil?
        return "Due on receipt" if days.zero?

        "Net #{days} days"
      end

      def money(amount)
        "#{currency} #{format('%.2f', amount.to_d)}"
      end
    end
  end
end
