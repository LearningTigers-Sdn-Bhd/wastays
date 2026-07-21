# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class StatementsIndexPresenter
      PER_PAGE = 25

      attr_reader :account, :params

      def initialize(account:, params:)
        @account = account
        @params = params
      end

      def rows
        @rows ||= paginated_relationships.map { |relationship| Row.new(relationship) }
      end

      def pagination
        paginated_relationships
      end

      def query
        params[:query].to_s.strip
      end

      def pagination_params
        { query: query.presence }.compact
      end

      private

      def relationships
        scope = account.hotel_corporate_accounts
          .active
          .includes(
            :ar_invoices,
            :hotel,
            ar_payments: { ar_payment_allocations: :reversal }
          )
          .joins(:hotel)
          .order(Arel.sql("LOWER(hotels.name) ASC"), :id)

        return scope if query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        scope.where("hotels.name ILIKE :query", query: pattern)
      end

      def paginated_relationships
        @paginated_relationships ||= relationships.page(params[:page]).per(PER_PAGE)
      end

      class Row
        attr_reader :relationship

        def initialize(relationship)
          @relationship = relationship
        end

        def hotel_name
          relationship.hotel.name
        end

        def payment_terms
          days = relationship.payment_terms_days
          return "Not set" if days.nil?
          return "Due on receipt" if days.zero?

          "Net #{days} days"
        end

        def last_activity
          dates = relationship.ar_invoices.reject(&:void?).map(&:issued_on) + relationship.ar_payments.map(&:received_at)
          dates.compact.max&.strftime("%d %b %Y") || "No activity"
        end

        def balance_labels
          grouped = Hash.new(0.to_d)
          relationship.ar_invoices.reject(&:void?).each { |invoice| grouped[invoice.currency] += invoice.amount.to_d }
          relationship.ar_payments.each { |payment| grouped[payment.currency] -= payment.amount.to_d }
          grouped[relationship.credit_currency] ||= 0.to_d
          grouped.sort.map { |currency, amount| "#{currency} #{format('%.2f', amount)}" }
        end

        def unapplied_labels
          grouped = relationship.ar_payments.group_by(&:currency).transform_values do |payments|
            payments.sum(&:unallocated_amount)
          end
          grouped[relationship.credit_currency] ||= 0.to_d
          grouped.sort.map { |currency, amount| "#{currency} #{format('%.2f', amount)}" }
        end
      end
    end
  end
end
