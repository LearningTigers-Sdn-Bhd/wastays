# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class StatementPresenter
      include Pagy::Method

      PER_PAGE = 50

      attr_reader :report, :params, :request

      def initialize(report:, params:, request:)
        @report = report
        @params = params
        @request = request
      end

      delegate :corporate_account, :contact_email, :start_date, :end_date, :currency,
        :available_currencies, :opening_balance, :period_invoices, :period_payments,
        :closing_balance, :unapplied_credit, :aging, :notes, to: :report

      def paginated_rows
        pagination_pair.last
      end

      def pagination
        pagination_pair.first
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

      private

      def pagination_pair
        @pagination_pair ||= pagy(:offset, LedgerCollection.new(report.ledger), request: request, limit: PER_PAGE)
      end

      class LedgerCollection
        def initialize(ledger)
          @ledger = ledger
        end

        def count
          @ledger.count
        end

        def offset(value)
          Window.new(@ledger, value)
        end

        class Window
          def initialize(ledger, offset)
            @ledger = ledger
            @offset = offset
          end

          def limit(value)
            @ledger.page(offset: @offset, limit: value)
          end
        end
      end
    end
  end
end
