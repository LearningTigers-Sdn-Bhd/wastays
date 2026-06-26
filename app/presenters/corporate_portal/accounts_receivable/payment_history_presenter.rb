# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class PaymentHistoryPresenter
      PER_PAGE = 25

      STATUS_OPTIONS = [
        { key: "unapplied", label: "Unapplied", icon: "wallet-cards", class: "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700" },
        { key: "partially_allocated", label: "Partially Allocated", icon: "circle-dollar-sign", class: "peer-checked:border-amber-400 peer-checked:bg-amber-50 peer-checked:text-amber-700" },
        { key: "fully_allocated", label: "Fully Allocated", icon: "circle-check", class: "peer-checked:border-emerald-400 peer-checked:bg-emerald-50 peer-checked:text-emerald-700" },
        { key: "pending", label: "Pending Attempts", icon: "circle-dot", class: "peer-checked:border-blue-400 peer-checked:bg-blue-50 peer-checked:text-blue-700" },
        { key: "failed", label: "Failed Attempts", icon: "circle-slash", class: "peer-checked:border-slate-500 peer-checked:bg-slate-100 peer-checked:text-slate-700" }
      ].freeze

      Metric = Struct.new(:label, :amounts, :description, :icon, :class_name, keyword_init: true)
      HotelOption = Struct.new(:id, :name, keyword_init: true)

      attr_reader :account, :params

      def initialize(account:, params:)
        @account = account
        @params = params
      end

      def rows
        @rows ||= Kaminari.paginate_array(all_rows.sort_by(&:sort_time).reverse).page(params[:page]).per(PER_PAGE)
      end

      def pagination
        rows
      end

      def hotel_options
        @hotel_options ||= account.hotel_corporate_accounts
          .active
          .includes(:hotel)
          .sort_by { |relationship| relationship.hotel.name.to_s.downcase }
          .map { |relationship| HotelOption.new(id: relationship.hotel_id, name: relationship.hotel.name) }
      end

      def status_options
        STATUS_OPTIONS
      end

      def selected_status
        @selected_status ||= STATUS_OPTIONS.any? { |option| option[:key] == params[:status].to_s } ? params[:status].to_s : nil
      end

      def selected_hotel_id
        @selected_hotel_id ||= begin
          requested_id = params[:hotel_id].to_s
          hotel_options.any? { |option| option.id.to_s == requested_id } ? requested_id : nil
        end
      end

      def received_from
        @received_from ||= parse_date(params[:received_from])
      end

      def received_to
        @received_to ||= parse_date(params[:received_to])
      end

      def query
        params[:query].to_s.strip
      end

      def filters_active?
        query.present? || selected_status.present? || selected_hotel_id.present? || received_from.present? || received_to.present?
      end

      def pagination_params
        {
          query: query.presence,
          status: selected_status,
          hotel_id: selected_hotel_id,
          received_from: received_from&.iso8601,
          received_to: received_to&.iso8601
        }.compact
      end

      def summary_metrics
        [
          Metric.new(
            label: "Received This Month",
            amounts: formatted_amounts(received_this_month),
            description: "#{Date.current.strftime("%B %Y")} payments",
            icon: "landmark",
            class_name: "bg-blue-50 text-blue-700"
          ),
          Metric.new(
            label: "Allocated This Month",
            amounts: formatted_amounts(allocated_this_month),
            description: "Active allocations from this month's receipts",
            icon: "circle-check",
            class_name: "bg-emerald-50 text-emerald-700"
          ),
          Metric.new(
            label: "Total Unapplied",
            amounts: formatted_amounts(total_unapplied),
            description: "Received funds not assigned to invoices",
            icon: "wallet-cards",
            class_name: "bg-amber-50 text-amber-700"
          ),
          Metric.new(
            label: "Needs Allocation",
            amounts: [ needs_allocation_count.to_s ],
            description: "Payments with an unapplied balance",
            icon: "triangle-alert",
            class_name: "bg-red-50 text-red-700"
          )
        ]
      end

      private

      def all_rows
        intent_rows + legacy_payment_rows
      end

      def intent_rows
        scope = CorporateArPaymentIntent.where(corporate_account: account)
          .includes(:hotel, :ar_payment)

        scope = scope.where(hotel_id: selected_hotel_id) if selected_hotel_id.present?

        if query.present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.joins(:hotel).where(
            "corporate_ar_payment_intents.external_reference ILIKE :query OR corporate_ar_payment_intents.gateway_order_id ILIKE :query OR hotels.name ILIKE :query",
            query: pattern
          )
        end

        if received_from.present?
          scope = scope.where("COALESCE(corporate_ar_payment_intents.captured_at, corporate_ar_payment_intents.created_at) >= ?", received_from.beginning_of_day)
        end
        if received_to.present?
          scope = scope.where("COALESCE(corporate_ar_payment_intents.captured_at, corporate_ar_payment_intents.created_at) <= ?", received_to.end_of_day)
        end

        # Preload associations for memory-based allocation status checks to avoid N+1 queries
        scope = scope.includes(ar_payment: { ar_payment_allocations: :reversal })

        rows = scope.map { |intent| IntentRow.new(intent) }

        if selected_status.present?
          rows = rows.select do |row|
            case selected_status
            when "unapplied"
              row.intent.captured? && row.intent.ar_payment.present? && row.intent.ar_payment.allocation_status == "unapplied"
            when "partially_allocated"
              row.intent.captured? && row.intent.ar_payment.present? && row.intent.ar_payment.allocation_status == "partially_allocated"
            when "fully_allocated"
              row.intent.captured? && row.intent.ar_payment.present? && row.intent.ar_payment.allocation_status == "fully_allocated"
            when "failed"
              %w[failed expired cancelled].include?(row.intent.status)
            when "pending"
              %w[pending checkout_initiated].include?(row.intent.status)
            else
              true
            end
          end
        end

        rows
      end

      def legacy_payment_rows
        if selected_status.present? && %w[pending failed].include?(selected_status)
          return []
        end

        scope = ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .includes(:hotel)
          .where.not(id: CorporateArPaymentIntent.where.not(ar_payment_id: nil).select(:ar_payment_id))

        scope = scope.where(hotel_id: selected_hotel_id) if selected_hotel_id.present?

        if query.present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.joins(:hotel).where(
            "ar_payments.reference_number ILIKE :query OR hotels.name ILIKE :query",
            query: pattern
          )
        end

        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?

        # Preload associations for memory-based allocation status checks
        scope = scope.includes(ar_payment_allocations: :reversal)

        rows = scope.map { |payment| PaymentRow.new(payment) }

        if selected_status.present?
          rows = rows.select do |row|
            case selected_status
            when "unapplied"
              row.payment.allocation_status == "unapplied"
            when "partially_allocated"
              row.payment.allocation_status == "partially_allocated"
            when "fully_allocated"
              row.payment.allocation_status == "fully_allocated"
            else
              true
            end
          end
        end

        rows
      end

      # Metrics Calculators
      def received_this_month
        intents = CorporateArPaymentIntent.where(corporate_account: account, status: "captured")
          .where(captured_at: Date.current.beginning_of_month.beginning_of_day..Date.current.end_of_month.end_of_day)
          .group(:currency).sum(:amount)

        legacies = ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where(received_at: Date.current.beginning_of_month..Date.current.end_of_month)
          .where.not(id: CorporateArPaymentIntent.where.not(ar_payment_id: nil).select(:ar_payment_id))
          .group(:currency).sum(:amount)

        totals = Hash.new(0.to_d)
        intents.each { |curr, amt| totals[curr.to_s.upcase] += amt.to_d }
        legacies.each { |curr, amt| totals[curr.to_s.upcase] += amt.to_d }
        totals
      end

      def allocated_this_month
        ArPaymentAllocation.active
          .joins(ar_payment: :hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where(created_at: Date.current.beginning_of_month.beginning_of_day..Date.current.end_of_month.end_of_day)
          .group("ar_payments.currency")
          .sum("ar_payment_allocations.amount")
      end

      def total_unapplied
        unapplied = Hash.new(0.to_d)

        ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where.not(id: CorporateArPaymentIntent.where.not(ar_payment_id: nil).select(:ar_payment_id))
          .includes(ar_payment_allocations: :reversal)
          .find_each do |pmt|
            unapplied[pmt.currency.to_s.upcase] += pmt.unallocated_amount
          end

        CorporateArPaymentIntent.where(corporate_account: account, status: "captured")
          .includes(ar_payment: { ar_payment_allocations: :reversal })
          .find_each do |intent|
            if intent.ar_payment
              unapplied[intent.currency.to_s.upcase] += intent.ar_payment.unallocated_amount
            else
              unapplied[intent.currency.to_s.upcase] += intent.amount.to_d
            end
          end

        unapplied
      end

      def needs_allocation_count
        count = 0

        ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where.not(id: CorporateArPaymentIntent.where.not(ar_payment_id: nil).select(:ar_payment_id))
          .includes(ar_payment_allocations: :reversal)
          .find_each do |pmt|
            count += 1 if pmt.unallocated_amount.positive?
          end

        CorporateArPaymentIntent.where(corporate_account: account, status: "captured")
          .includes(ar_payment: { ar_payment_allocations: :reversal })
          .find_each do |intent|
            if intent.ar_payment
              count += 1 if intent.ar_payment.unallocated_amount.positive?
            else
              count += 1 if intent.amount.to_d.positive?
            end
          end

        count
      end

      def formatted_amounts(amounts)
        normalized = amounts.transform_keys { |k| k.to_s.upcase }
        if normalized.empty?
          default_currency = account.hotel_corporate_accounts.first&.credit_currency || "MYR"
          normalized = { default_currency => 0.to_d }
        end

        normalized.sort.map do |currency, amount|
          "#{currency} #{format("%.2f", amount.to_d)}"
        end
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end

      class IntentRow
        attr_reader :intent

        def initialize(intent)
          @intent = intent
        end

        def sort_time = intent.created_at
        def reference = intent.external_reference.presence || intent.gateway_order_id.presence || "Attempt ##{intent.id}"
        def hotel_name = intent.hotel.name
        def received_on = intent.captured_at&.strftime("%d %b %Y") || "—"
        def method = intent.ar_payment&.payment_method&.humanize || intent.gateway.titleize
        def amount_label = money(intent.amount)
        def allocated_label = intent.ar_payment ? money(intent.ar_payment.allocated_amount) : "—"
        def unapplied_label = intent.ar_payment ? money(intent.ar_payment.unallocated_amount) : "—"
        def status_label = intent.ar_payment&.allocation_status&.humanize || intent.status.humanize
        def path = Rails.application.routes.url_helpers.corporate_ar_payment_path(intent)

        private

        def money(amount)
          "#{intent.currency} #{format('%.2f', amount.to_d)}"
        end
      end

      class PaymentRow
        attr_reader :payment

        def initialize(payment)
          @payment = payment
        end

        def sort_time = payment.received_at.to_time
        def reference = payment.reference_number
        def hotel_name = payment.hotel.name
        def received_on = payment.received_at.strftime("%d %b %Y")
        def method = payment.payment_method.humanize
        def amount_label = money(payment.amount)
        def allocated_label = money(payment.allocated_amount)
        def unapplied_label = money(payment.unallocated_amount)
        def status_label = payment.allocation_status.humanize
        def path = Rails.application.routes.url_helpers.corporate_ar_payment_path(payment, legacy: true)

        private

        def money(amount)
          "#{payment.currency} #{format('%.2f', amount.to_d)}"
        end
      end
    end
  end
end
