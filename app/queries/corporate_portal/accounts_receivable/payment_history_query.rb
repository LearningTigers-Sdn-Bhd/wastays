# frozen_string_literal: true

module CorporatePortal
  module AccountsReceivable
    class PaymentHistoryQuery
      Locator = Data.define(:source_type, :source_id, :sort_time)
      Result = Data.define(:count, :locators)

      SOURCE_ORDER = { intent: 0, payment: 1, submission: 2 }.freeze
      ALLOCATION_STATUSES = %w[unapplied partially_allocated fully_allocated].freeze

      def initialize(account:, query:, status:, hotel_id:, received_from:, received_to:)
        @account = account
        @query = query
        @status = status
        @hotel_id = hotel_id
        @received_from = received_from
        @received_to = received_to
      end

      def call(page:, limit:)
        scopes = source_scopes
        count = scopes.values.sum(&:count)
        candidate_limit = [ page * limit, count ].min
        locators = scopes.flat_map do |source_type, scope|
          locator_rows(source_type, scope, candidate_limit)
        end

        Result.new(count:, locators: locators.sort_by { |locator| locator_sort_key(locator) })
      end

      private

      attr_reader :account, :query, :status, :hotel_id, :received_from, :received_to

      def source_scopes
        {
          intent: intent_scope,
          payment: payment_scope,
          submission: submission_scope
        }
      end

      def intent_scope
        return CorporateArPaymentIntent.none if %w[pending_review rejected].include?(status)

        scope = CorporateArPaymentIntent.where(corporate_account: account)
        scope = scope.where(hotel_id:) if hotel_id.present?
        scope = search_intents(scope) if query.present?
        scope = scope.where("COALESCE(corporate_ar_payment_intents.captured_at, corporate_ar_payment_intents.created_at) >= ?", received_from.beginning_of_day) if received_from.present?
        scope = scope.where("COALESCE(corporate_ar_payment_intents.captured_at, corporate_ar_payment_intents.created_at) <= ?", received_to.end_of_day) if received_to.present?

        case status
        when "pending"
          scope.where(status: %w[pending checkout_initiated])
        when "failed"
          scope.where(status: %w[failed expired cancelled])
        when *ALLOCATION_STATUSES
          scope.joins(:ar_payment).where(status: "captured").where(allocation_status_condition(status))
        else
          scope
        end
      end

      def payment_scope
        return ArPayment.none if %w[pending failed pending_review rejected].include?(status)

        scope = ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where.not(id: CorporateArPaymentIntent.where.not(ar_payment_id: nil).select(:ar_payment_id))
        scope = scope.where(hotel_id:) if hotel_id.present?
        scope = search_payments(scope) if query.present?
        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?
        scope = scope.where(allocation_status_condition(status)) if ALLOCATION_STATUSES.include?(status)
        scope
      end

      def submission_scope
        return ArPaymentSubmission.none if %w[unapplied partially_allocated fully_allocated pending failed].include?(status)

        scope = ArPaymentSubmission.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: account.id })
          .where.not(status: "approved")
        scope = scope.where(hotel_id:) if hotel_id.present?
        scope = search_submissions(scope) if query.present?
        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?
        scope = scope.where(status: "pending") if status == "pending_review"
        scope = scope.where(status: "rejected") if status == "rejected"
        scope
      end

      def locator_rows(source_type, scope, limit)
        return [] if limit.zero?

        time_column = source_type == :payment ? :received_at : :created_at
        scope.reorder(time_column => :desc, id: :desc).limit(limit).pluck(:id, time_column).map do |id, sort_time|
          Locator.new(source_type:, source_id: id, sort_time: sort_time.to_time)
        end
      end

      def locator_sort_key(locator)
        [ -locator.sort_time.to_f, SOURCE_ORDER.fetch(locator.source_type), -locator.source_id ]
      end

      def allocation_status_condition(requested_status)
        allocated = <<~SQL.squish
          COALESCE((
            SELECT SUM(ar_payment_allocations.amount)
            FROM ar_payment_allocations
            LEFT JOIN ar_payment_allocation_reversals
              ON ar_payment_allocation_reversals.ar_payment_allocation_id = ar_payment_allocations.id
            WHERE ar_payment_allocations.ar_payment_id = ar_payments.id
              AND ar_payment_allocation_reversals.id IS NULL
          ), 0)
        SQL

        case requested_status
        when "unapplied"
          "#{allocated} = 0"
        when "fully_allocated"
          "#{allocated} = ar_payments.amount"
        else
          "#{allocated} > 0 AND #{allocated} < ar_payments.amount"
        end
      end

      def search_intents(scope)
        scope.joins(:hotel).where(
          "corporate_ar_payment_intents.external_reference ILIKE :query OR corporate_ar_payment_intents.gateway_order_id ILIKE :query OR hotels.name ILIKE :query",
          query: search_pattern
        )
      end

      def search_payments(scope)
        scope.joins(:hotel).where(
          "ar_payments.reference_number ILIKE :query OR hotels.name ILIKE :query",
          query: search_pattern
        )
      end

      def search_submissions(scope)
        scope.joins(:hotel).where(
          "ar_payment_submissions.reference_number ILIKE :query OR hotels.name ILIKE :query",
          query: search_pattern
        )
      end

      def search_pattern
        @search_pattern ||= "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      end
    end
  end
end
