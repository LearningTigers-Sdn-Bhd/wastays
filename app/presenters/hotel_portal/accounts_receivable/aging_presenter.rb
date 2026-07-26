# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class AgingPresenter
      Metric = Struct.new(:label, :amounts, :icon, :class_name, keyword_init: true)

      ACCOUNT_TYPE_OPTIONS = HotelCorporateAccount::ACCOUNT_TYPES.map { |type| [ type.humanize, type ] }.freeze

      attr_reader :report, :query, :account_type

      def initialize(report:, query: nil, account_type: nil)
        @report = report
        @query = query.to_s.strip.presence
        @account_type = account_type.presence_in(HotelCorporateAccount::ACCOUNT_TYPES)
      end

      delegate :as_of_date, to: :report

      def account_type_options = ACCOUNT_TYPE_OPTIONS

      def filters_active?
        query.present? || account_type.present?
      end

      def rows
        @rows ||= begin
          filtered = report.rows
          filtered = filtered.select { |row| row.corporate_account.name.downcase.include?(query.downcase) } if query.present?
          filtered = filtered.select { |row| row.hotel_corporate_account.account_type == account_type } if account_type.present?
          filtered.map { |row| Row.new(row) }
        end
      end

      def summary_metrics
        [
          metric("Current", :current, "circle-check", "bg-emerald-50 text-emerald-700"),
          metric("1–30 days", :days_1_30, "clock-3", "bg-amber-50 text-amber-700"),
          metric("31–60 days", :days_31_60, "clock-alert", "bg-orange-50 text-orange-700"),
          metric("61–90 days", :days_61_90, "triangle-alert", "bg-red-50 text-red-700"),
          metric("90+ days", :days_over_90, "octagon-alert", "bg-rose-50 text-rose-700"),
          Metric.new(
            label: "Total outstanding",
            amounts: amounts_for(&:total),
            icon: "wallet-cards",
            class_name: "bg-muted text-foreground"
          )
        ]
      end

      private

      def metric(label, bucket, icon, class_name)
        Metric.new(
          label: label,
          amounts: amounts_for { |totals| totals.public_send(bucket) },
          icon: icon,
          class_name: class_name
        )
      end

      def amounts_for
        totals = report.totals
        totals = { report.hotel.default_currency => ArInvoices::AgingReport::BucketTotals.new } if totals.empty?

        totals.sort.map do |currency, bucket_totals|
          "#{currency} #{format('%.2f', yield(bucket_totals).to_d)}"
        end
      end

      class Row
        attr_reader :row

        def initialize(row)
          @row = row
        end

        delegate :hotel_corporate_account, :corporate_account, :currency, :buckets, :total_outstanding, to: :row

        def corporate_account_name
          corporate_account.name
        end

        def credit_limit_label
          return "Not set" if row.credit_limit.blank?

          money(row.credit_limit, row.credit_currency)
        end

        def current_label
          amount(row.buckets.current)
        end

        def days_1_30_label
          amount(row.buckets.days_1_30)
        end

        def days_31_60_label
          amount(row.buckets.days_31_60)
        end

        def days_61_90_label
          amount(row.buckets.days_61_90)
        end

        def days_over_90_label
          amount(row.buckets.days_over_90)
        end

        def total_outstanding_label
          money(row.total_outstanding, row.currency)
        end

        def credit_status_label
          return "Not comparable" unless row.credit_comparable?

          case row.credit_exposure.warning_state
          when "near_limit" then "Near limit"
          when "over_limit" then "Over limit"
          when "no_limit" then "No limit"
          else "OK"
          end
        end

        def credit_status_class
          return "border-border bg-muted text-muted-foreground" unless row.credit_comparable?

          case row.credit_exposure.warning_state
          when "near_limit" then "border-amber-200 bg-amber-50 text-amber-800"
          when "over_limit" then "border-red-200 bg-red-50 text-red-700"
          when "no_limit" then "border-border bg-muted text-foreground"
          else "border-emerald-200 bg-emerald-50 text-emerald-700"
          end
        end

        def credit_status_description
          return "Credit limit is configured in #{row.credit_currency}" unless row.credit_comparable?
          return row.credit_exposure.warning_message if row.credit_exposure.warning?

          usage = row.credit_exposure.usage_percentage
          usage.present? ? "#{usage.to_i}% of credit limit used" : "Within credit limit"
        end

        private

        def amount(value)
          format("%.2f", value.to_d)
        end

        def money(value, currency)
          "#{currency} #{amount(value)}"
        end
      end
    end
  end
end
