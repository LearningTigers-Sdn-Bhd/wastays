# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    class PaymentRecordQuery
      Locator = Data.define(:source_type, :source_id, :sort_time)
      Result = Data.define(:count, :locators)

      SOURCE_ORDER = { submission: 0, payment: 1 }.freeze

      def initialize(hotel:, query:, status:, hotel_corporate_account_id:, received_from:, received_to:)
        @hotel = hotel
        @query = query
        @status = status
        @hotel_corporate_account_id = hotel_corporate_account_id
        @received_from = received_from
        @received_to = received_to
      end

      def call(page:, limit:)
        scopes = { payment: payment_scope, submission: submission_scope }
        count = scopes.values.sum(&:count)
        candidate_limit = [ page * limit, count ].min
        locators = scopes.flat_map do |source_type, scope|
          locator_rows(source_type, scope, candidate_limit)
        end

        Result.new(count:, locators: locators.sort_by { |locator| locator_sort_key(locator) })
      end

      private

      attr_reader :hotel, :query, :status, :hotel_corporate_account_id, :received_from, :received_to

      def payment_scope
        return ArPayment.none if %w[pending rejected].include?(status)

        scope = hotel.ar_payments
        scope = search_payments(scope) if query.present?
        scope = scope.where(hotel_corporate_account_id:) if hotel_corporate_account_id.present?
        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?
        scope
      end

      def submission_scope
        scope = hotel.ar_payment_submissions.where.not(status: "approved")
        scope = search_submissions(scope) if query.present?
        scope = scope.where(hotel_corporate_account_id:) if hotel_corporate_account_id.present?
        scope = scope.where(received_at: received_from..) if received_from.present?
        scope = scope.where(received_at: ..received_to) if received_to.present?
        scope = scope.where(status:) if status.in?(%w[pending rejected])
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

      def search_payments(scope)
        scope.joins(hotel_corporate_account: :corporate_account).where(
          "ar_payments.reference_number ILIKE :query OR accounts.name ILIKE :query",
          query: search_pattern
        )
      end

      def search_submissions(scope)
        scope.joins(hotel_corporate_account: :corporate_account).where(
          "ar_payment_submissions.reference_number ILIKE :query OR accounts.name ILIKE :query",
          query: search_pattern
        )
      end

      def search_pattern
        @search_pattern ||= "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      end
    end
  end
end
