# frozen_string_literal: true

module ArInvoices
  class AgingReport
    BucketTotals = Struct.new(:current, :days_1_30, :days_31_60, :days_61_90, :days_over_90, keyword_init: true) do
      def total
        current.to_d + days_1_30.to_d + days_31_60.to_d + days_61_90.to_d + days_over_90.to_d
      end
    end

    Row = Struct.new(
      :hotel_corporate_account,
      :corporate_account,
      :currency,
      :credit_limit,
      :credit_currency,
      :buckets,
      :total_outstanding,
      :credit_exposure,
      keyword_init: true
    ) do
      def credit_comparable?
        currency == credit_currency
      end
    end

    Result = Struct.new(:hotel, :as_of_date, :rows, :totals, keyword_init: true)

    def self.call(hotel:, as_of_date: nil, account_types: nil, query: nil)
      new(hotel: hotel, as_of_date: as_of_date, account_types: account_types, query: query).call
    end

    def initialize(hotel:, as_of_date: nil, account_types: nil, query: nil)
      @hotel = hotel
      @as_of_date = (as_of_date.presence || hotel.current_business_date).to_date
      @account_types = Array(account_types).presence
      @query = query.to_s.strip.presence
    end

    def call
      rows = grouped_invoices.map { |(relationship, currency), invoices| row_for(relationship, currency, invoices) }
        .sort_by { |row| [ -row.total_outstanding, row.corporate_account.name.to_s.downcase, row.currency ] }
      Result.new(hotel: @hotel, as_of_date: @as_of_date, rows: rows, totals: totals_for(rows))
    end

    private

    def invoices
      @invoices ||= begin
        scope = @hotel.receivables
          .with_open_balance
          .includes(hotel_corporate_account: :corporate_account)
        scope = scope.joins(:hotel_corporate_account).where(hotel_corporate_accounts: { account_type: @account_types }) if @account_types.present?
        if @query.present?
          scope = scope.joins(hotel_corporate_account: :corporate_account)
            .where("accounts.name ILIKE ?", "%#{Account.sanitize_sql_like(@query)}%")
        end
        scope.to_a
      end
    end

    def grouped_invoices
      invoices.group_by { |invoice| [ invoice.hotel_corporate_account, invoice.currency ] }
    end

    def row_for(relationship, currency, invoices)
      buckets = empty_buckets
      invoices.each do |invoice|
        bucket_name = bucket_for(invoice)
        buckets[bucket_name] += invoice.outstanding_amount.to_d
      end

      bucket_totals = BucketTotals.new(**buckets)
      credit_exposure = ArInvoices::CreditExposure.call(hotel_corporate_account: relationship)
      Row.new(
        hotel_corporate_account: relationship,
        corporate_account: relationship.corporate_account,
        currency: currency,
        credit_limit: relationship.credit_limit,
        credit_currency: credit_exposure.credit_currency,
        buckets: bucket_totals,
        total_outstanding: bucket_totals.total,
        credit_exposure: credit_exposure
      )
    end

    def bucket_for(invoice)
      days_overdue = (@as_of_date - invoice.due_on).to_i
      return :current if days_overdue <= 0
      return :days_1_30 if days_overdue <= 30
      return :days_31_60 if days_overdue <= 60
      return :days_61_90 if days_overdue <= 90

      :days_over_90
    end

    def empty_buckets
      { current: 0.to_d, days_1_30: 0.to_d, days_31_60: 0.to_d, days_61_90: 0.to_d, days_over_90: 0.to_d }
    end

    def totals_for(rows)
      rows.group_by(&:currency).transform_values do |currency_rows|
        currency_rows.each_with_object(empty_buckets) do |row, totals|
          totals[:current] += row.buckets.current.to_d
          totals[:days_1_30] += row.buckets.days_1_30.to_d
          totals[:days_31_60] += row.buckets.days_31_60.to_d
          totals[:days_61_90] += row.buckets.days_61_90.to_d
          totals[:days_over_90] += row.buckets.days_over_90.to_d
        end.then { |totals| BucketTotals.new(**totals) }
      end
    end
  end
end
