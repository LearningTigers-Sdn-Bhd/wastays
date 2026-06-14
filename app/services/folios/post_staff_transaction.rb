# frozen_string_literal: true

require "ostruct"

module Folios
  class PostStaffTransaction
    ALLOWED_CATEGORIES = {
      "charge" => %w[other],
      "payment" => %w[cash refund],
      "adjustment" => %w[adjustment correction discount write_off other]
    }.freeze

    def self.call(folio:, user:, transaction_type:, category:, amount:, description:, posting_date: nil, options: {})
      new(
        folio: folio,
        user: user,
        transaction_type: transaction_type,
        category: category,
        amount: amount,
        description: description,
        posting_date: posting_date,
        options: options
      ).call
    end

    def initialize(folio:, user:, transaction_type:, category:, amount:, description:, posting_date: nil, options: {})
      @folio = folio
      @user = user
      @transaction_type = transaction_type.to_s
      @category = category.to_s
      @amount = amount.to_d
      @description = description.to_s.strip
      @posting_date = posting_date.presence || @folio.hotel.current_business_date
      @options = options
    end

    def call
      return failure("Transaction type is not allowed.") unless allowed_transaction_type?
      return failure("Category is not allowed for #{@transaction_type} transactions.") unless allowed_category?
      return failure("Description can't be blank.") if @description.blank?
      return failure("Amount must be greater than zero.") if requires_positive_amount? && !@amount.positive?
      return failure("Amount can't be zero.") if @transaction_type == "adjustment" && @amount.zero?

      Folios::InsertTransaction.new(
        booking_folio: @folio,
        amount: normalized_amount,
        transaction_type: @transaction_type,
        category: @category,
        user: @user,
        description: @description,
        posting_date: @posting_date,
        options: @options.merge(
          metadata: (@options[:metadata] || {}).merge(
            posting_source: @options[:posting_source].presence || "staff",
            posted_from: "booking_show",
            posted_by_user_id: @user&.id
          )
        )
      ).call
    end

    private

    def allowed_transaction_type?
      ALLOWED_CATEGORIES.key?(@transaction_type)
    end

    def allowed_category?
      @category.in?(ALLOWED_CATEGORIES.fetch(@transaction_type, []))
    end

    def normalized_amount
      return -@amount.abs if @transaction_type == "payment" && @category == "refund"

      @amount
    end

    def requires_positive_amount?
      @transaction_type == "charge" || @transaction_type == "payment"
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
