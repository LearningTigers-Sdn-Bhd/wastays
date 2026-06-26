# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class StatementsIndexPresenter
      PER_PAGE = 25

      attr_reader :hotel, :params

      def initialize(hotel:, params:)
        @hotel = hotel
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
        scope = hotel.hotel_corporate_accounts
          .includes(
            :ar_invoices,
            corporate_account: :users,
            ar_payments: { ar_payment_allocations: :reversal }
          )
          .joins(:corporate_account)
          .order(Arel.sql("LOWER(accounts.name) ASC"), :id)

        return scope if query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        matching_ids = hotel.hotel_corporate_accounts
          .left_joins(corporate_account: :users)
          .where("accounts.name ILIKE :query OR users.email ILIKE :query", query: pattern)
          .select(:id)
        scope.where(id: matching_ids)
      end

      def paginated_relationships
        @paginated_relationships ||= relationships.page(params[:page]).per(PER_PAGE)
      end

      class Row
        attr_reader :relationship

        def initialize(relationship)
          @relationship = relationship
        end

        def corporate_account_name
          relationship.corporate_account.name
        end

        def contact_email
          relationship.corporate_account.users.min_by(&:id)&.email.presence || "—"
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
