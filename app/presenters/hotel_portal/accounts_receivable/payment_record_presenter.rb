# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class PaymentRecordPresenter
      PER_PAGE = 25
      STATUS_OPTIONS = [
        [ "Unapplied", "unapplied" ],
        [ "Partially allocated", "partially_allocated" ],
        [ "Fully allocated", "fully_allocated" ],
        [ "Pending Review", "pending" ],
        [ "Rejected", "rejected" ]
      ].freeze
      ALLOCATED_SQL = <<~SQL.squish.freeze
        COALESCE((
          SELECT SUM(allocations.amount)
          FROM ar_payment_allocations allocations
          LEFT JOIN ar_payment_allocation_reversals reversals
            ON reversals.ar_payment_allocation_id = allocations.id
          WHERE allocations.ar_payment_id = ar_payments.id
            AND reversals.id IS NULL
        ), 0)
      SQL

      Metric = Struct.new(:label, :amounts, :description, :icon, :class_name, keyword_init: true)
      CorporateAccountOption = Struct.new(:id, :name, keyword_init: true)

      attr_reader :hotel, :params

      def initialize(hotel:, params:)
        @hotel = hotel
        @params = params
      end

      def paginated_rows
        @paginated_rows ||= Kaminari.paginate_array(all_rows.sort_by(&:sort_time).reverse).page(params[:page]).per(PER_PAGE)
      end

      def pagination
        paginated_rows
      end

      def summary_metrics
        [
          metric("Received This Month", received_this_month, "Payments received in the current business month", "landmark", "bg-blue-50 text-blue-700"),
          metric("Allocated This Month", allocated_this_month, "Active allocations from this month's receipts", "circle-check", "bg-emerald-50 text-emerald-700"),
          metric("Total Unapplied", total_unapplied, "Received funds not assigned to invoices", "wallet-cards", "bg-amber-50 text-amber-700"),
          Metric.new(label: "Needs Allocation", amounts: [ needs_allocation_count.to_s ], description: "Payments with an unapplied balance", icon: "triangle-alert", class_name: "bg-red-50 text-red-700"),
          Metric.new(label: "Pending Submissions", amounts: [ pending_submissions_count.to_s ], description: "Agent bank-transfer slips awaiting review", icon: "upload", class_name: "bg-violet-50 text-violet-700")
        ]
      end

      def corporate_account_options
        @corporate_account_options ||= hotel.hotel_corporate_accounts
          .includes(:corporate_account)
          .sort_by { |relationship| relationship.corporate_account.name.to_s.downcase }
          .map { |relationship| CorporateAccountOption.new(id: relationship.id, name: relationship.corporate_account.name) }
      end

      def status_options
        STATUS_OPTIONS
      end

      def query
        params[:query].to_s.strip
      end

      def selected_status
        value = params[:status].to_s
        STATUS_OPTIONS.any? { |option| option.last == value } ? value : nil
      end

      def selected_corporate_account_id
        requested = params[:hotel_corporate_account_id].to_s
        corporate_account_options.any? { |option| option.id.to_s == requested } ? requested : nil
      end

      def received_from
        parse_date(params[:received_from])
      end

      def received_to
        parse_date(params[:received_to])
      end

      def filters_active?
        query.present? || selected_status.present? || selected_corporate_account_id.present? || received_from.present? || received_to.present?
      end

      private

      def all_rows
        payment_rows + submission_rows
      end

      def payment_scope
        hotel.ar_payments
          .select("ar_payments.*, #{ALLOCATED_SQL} AS active_allocated_amount")
          .includes(hotel_corporate_account: :corporate_account)
      end

      def payment_rows
        return [] if %w[pending rejected].include?(selected_status)

        scope = payment_scope
        if query.present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.joins(hotel_corporate_account: :corporate_account)
            .where("ar_payments.reference_number ILIKE :query OR accounts.name ILIKE :query", query: pattern)
        end
        scope = scope.where(hotel_corporate_account_id: selected_corporate_account_id) if selected_corporate_account_id.present?
        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?
        scope = apply_payment_status(scope)

        scope.map { |payment| PaymentRow.new(payment) }
      end

      def apply_payment_status(scope)
        case selected_status
        when "unapplied"
          scope.where("#{ALLOCATED_SQL} = 0")
        when "partially_allocated"
          scope.where("#{ALLOCATED_SQL} > 0 AND #{ALLOCATED_SQL} < ar_payments.amount")
        when "fully_allocated"
          scope.where("#{ALLOCATED_SQL} = ar_payments.amount")
        else
          scope
        end
      end

      def submission_rows
        return [] if %w[unapplied partially_allocated fully_allocated].include?(selected_status)

        scope = hotel.ar_payment_submissions
          .where.not(status: "approved")
          .includes(hotel_corporate_account: :corporate_account)

        if query.present?
          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope = scope.joins(hotel_corporate_account: :corporate_account)
            .where("ar_payment_submissions.reference_number ILIKE :query OR accounts.name ILIKE :query", query: pattern)
        end
        scope = scope.where(hotel_corporate_account_id: selected_corporate_account_id) if selected_corporate_account_id.present?
        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?
        scope = scope.where(status: selected_status) if selected_status.in?(%w[pending rejected])

        scope.map { |submission| SubmissionRow.new(hotel, submission) }
      end

      def business_month_scope
        date = hotel.current_business_date
        hotel.ar_payments.where(received_at: date.beginning_of_month..date.end_of_month)
      end

      def received_this_month
        business_month_scope.group(:currency).sum(:amount)
      end

      def allocated_this_month
        business_month_scope.left_joins(ar_payment_allocations: :reversal)
          .where(ar_payment_allocation_reversals: { id: nil })
          .group(:currency)
          .sum("ar_payment_allocations.amount")
      end

      def balance_rows
        @balance_rows ||= hotel.ar_payments
          .select("ar_payments.currency, ar_payments.amount, #{ALLOCATED_SQL} AS active_allocated_amount")
          .map { |payment| [ payment.currency, payment.amount.to_d, payment.active_allocated_amount.to_d ] }
      end

      def total_unapplied
        balance_rows.each_with_object(Hash.new(0.to_d)) do |(currency, amount, allocated), totals|
          totals[currency] += amount - allocated
        end
      end

      def needs_allocation_count
        balance_rows.count { |_currency, amount, allocated| allocated < amount }
      end

      def pending_submissions_count
        hotel.ar_payment_submissions.pending.count
      end

      def metric(label, amounts, description, icon, class_name)
        Metric.new(label: label, amounts: formatted_amounts(amounts), description: description, icon: icon, class_name: class_name)
      end

      def formatted_amounts(amounts)
        normalized = amounts.transform_keys(&:to_s)
        normalized[hotel.default_currency] = 0.to_d if normalized.empty?
        normalized.sort.map { |currency, amount| "#{currency} #{format('%.2f', amount.to_d)}" }
      end

      def parse_date(value)
        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end

      class PaymentRow
        attr_reader :payment

        def initialize(payment)
          @payment = payment
        end

        def sort_time
          payment.received_at.to_time
        end

        def kind
          :payment
        end

        def account_name
          payment.corporate_account.name
        end

        def reference
          payment.reference_number
        end

        def received_on
          payment.received_at.strftime("%d %b %Y")
        end

        def method_label
          payment.payment_method.humanize
        end

        def amount_label
          money(payment.amount)
        end

        def allocated_label
          money(allocated_amount)
        end

        def unapplied_label
          money(unapplied_amount)
        end

        def status
          return "unapplied" if allocated_amount.zero?
          return "fully_allocated" if unapplied_amount.zero?

          "partially_allocated"
        end

        def status_label
          status.humanize
        end

        def status_class
          case status
          when "unapplied" then "border-red-200 bg-red-50 text-red-700"
          when "partially_allocated" then "border-amber-200 bg-amber-50 text-amber-700"
          else "border-emerald-200 bg-emerald-50 text-emerald-700"
          end
        end

        def status_title
          nil
        end

        def path(hotel)
          Rails.application.routes.url_helpers.hotel_ar_payment_path(hotel, payment)
        end

        private

        def allocated_amount
          payment.active_allocated_amount.to_d
        end

        def unapplied_amount
          payment.amount.to_d - allocated_amount
        end

        def money(amount)
          "#{payment.currency} #{format('%.2f', amount.to_d)}"
        end
      end

      class SubmissionRow
        attr_reader :hotel, :submission

        def initialize(hotel, submission)
          @hotel = hotel
          @submission = submission
        end

        def sort_time
          submission.created_at
        end

        def kind
          :submission
        end

        def account_name
          submission.hotel_corporate_account.corporate_account.name
        end

        def reference
          submission.reference_number
        end

        def received_on
          submission.received_at.strftime("%d %b %Y")
        end

        def method_label
          submission.payment_method.humanize
        end

        def amount_label
          money(submission.amount)
        end

        def allocated_label
          "—"
        end

        def unapplied_label
          "—"
        end

        def status
          submission.status
        end

        def status_label
          submission.pending? ? "Pending Review" : status.humanize
        end

        def status_class
          submission.pending? ? "border-violet-200 bg-violet-50 text-violet-700" : "border-slate-300 bg-slate-100 text-slate-700"
        end

        def status_title
          return nil unless submission.rejected? && submission.reviewed_at.present?

          "Rejected on #{submission.reviewed_at.strftime('%d %b %Y, %H:%M')}"
        end

        def path(hotel)
          routes = Rails.application.routes.url_helpers
          if submission.pending?
            routes.new_hotel_ar_payment_path(hotel, ar_payment_submission_id: submission.id)
          else
            routes.hotel_ar_payment_submission_path(hotel, submission)
          end
        end

        private

        def money(amount)
          "#{submission.currency} #{format('%.2f', amount.to_d)}"
        end
      end
    end
  end
end
