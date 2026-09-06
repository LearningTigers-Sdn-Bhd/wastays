# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class PaymentHistoryPresenter
      include Pagy::Method

      PER_PAGE = 25

      STATUS_OPTIONS = [
        { key: "unapplied", label: "Unapplied", icon: "wallet-cards", class: "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700" },
        { key: "partially_allocated", label: "Partially Allocated", icon: "circle-dollar-sign", class: "peer-checked:border-amber-400 peer-checked:bg-amber-50 peer-checked:text-amber-700" },
        { key: "fully_allocated", label: "Fully Allocated", icon: "circle-check", class: "peer-checked:border-emerald-400 peer-checked:bg-emerald-50 peer-checked:text-emerald-700" },
        { key: "pending", label: "Pending Attempts", icon: "circle-dot", class: "peer-checked:border-blue-400 peer-checked:bg-blue-50 peer-checked:text-blue-700" },
        { key: "failed", label: "Failed Attempts", icon: "circle-slash", class: "peer-checked:border-slate-500 peer-checked:bg-slate-100 peer-checked:text-slate-700" },
        { key: "pending_review", label: "Pending Bank Transfer Review", icon: "upload", class: "peer-checked:border-violet-400 peer-checked:bg-violet-50 peer-checked:text-violet-700" },
        { key: "rejected", label: "Rejected Bank Transfer", icon: "circle-x", class: "peer-checked:border-red-400 peer-checked:bg-red-50 peer-checked:text-red-700" }
      ].freeze

      Metric = Struct.new(:label, :amounts, :description, :icon, :class_name, keyword_init: true)
      HotelOption = Struct.new(:id, :name, keyword_init: true)

      attr_reader :account, :params, :request

      def initialize(account:, params:, request:)
        @account = account
        @params = params
        @request = request
      end

      def rows
        @rows ||= hydrate_rows(pagination_pair.last)
      end

      def pagination
        pagination_pair.first
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
          ),
          Metric.new(
            label: "Pending Bank Transfers",
            amounts: [ pending_submissions_count.to_s ],
            description: "Awaiting hotel review",
            icon: "upload",
            class_name: "bg-violet-50 text-violet-700"
          )
        ]
      end

      private

      def pagination_pair
        @pagination_pair ||= begin
          result = payment_history_query.call(page: requested_page, limit: PER_PAGE)
          pagy(:offset, result.locators, request: request, page: requested_page, limit: PER_PAGE, count: result.count)
        end
      end

      def payment_history_query
        CorporatePortal::AccountsReceivable::PaymentHistoryQuery.new(
          account: account,
          query: query,
          status: selected_status,
          hotel_id: selected_hotel_id,
          received_from: received_from,
          received_to: received_to
        )
      end

      def requested_page
        page = params[:page].to_i
        page.positive? ? page : 1
      end

      def hydrate_rows(locators)
        records = records_by_source(locators)
        locators.filter_map do |locator|
          record = records.dig(locator.source_type, locator.source_id)
          next unless record

          row_class(locator.source_type).new(record)
        end
      end

      def records_by_source(locators)
        ids = locators.group_by(&:source_type).transform_values { |items| items.map(&:source_id) }
        {
          intent: load_intents(ids.fetch(:intent, [])),
          payment: load_payments(ids.fetch(:payment, [])),
          submission: load_submissions(ids.fetch(:submission, []))
        }
      end

      def load_intents(ids)
        CorporateArPaymentIntent.where(corporate_account: account, id: ids)
          .includes(:hotel, ar_payment: { ar_payment_allocations: :reversal })
          .index_by(&:id)
      end

      def load_payments(ids)
        ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where(id: ids)
          .includes(:hotel, ar_payment_allocations: :reversal)
          .index_by(&:id)
      end

      def load_submissions(ids)
        ArPaymentSubmission.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where(id: ids)
          .includes(:hotel)
          .index_by(&:id)
      end

      def row_class(source_type)
        { intent: IntentRow, payment: PaymentRow, submission: SubmissionRow }.fetch(source_type)
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

      def pending_submissions_count
        ArPaymentSubmission.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where(status: "pending")
          .count
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

      class SubmissionRow
        attr_reader :submission

        def initialize(submission)
          @submission = submission
        end

        def sort_time = submission.created_at
        def reference = submission.reference_number
        def hotel_name = submission.hotel.name
        def received_on = submission.received_at.strftime("%d %b %Y")
        def method = submission.payment_method.humanize
        def amount_label = money(submission.amount)
        def allocated_label = "—"
        def unapplied_label = "—"
        def status_label = submission.pending? ? "Pending Review" : submission.status.humanize
        def path = Rails.application.routes.url_helpers.corporate_ar_payment_submission_path(submission)

        private

        def money(amount)
          "#{submission.currency} #{format('%.2f', amount.to_d)}"
        end
      end
    end
  end
end
