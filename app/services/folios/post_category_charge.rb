# frozen_string_literal: true

require "ostruct"

module Folios
  class PostCategoryCharge
    ALLOWED_CATEGORIES = %w[late_checkout_charge early_departure_charge].freeze

    def self.call(folio:, user:, category:, amount:, description: nil, metadata: {}, options: {})
      new(folio: folio, user: user, category: category, amount: amount, description: description, metadata: metadata, options: options).call
    end

    def initialize(folio:, user:, category:, amount:, description: nil, metadata: {}, options: {})
      @folio = folio
      @user = user
      @category = category.to_s
      @amount = amount.to_d
      @description = description.presence || default_description
      @metadata = metadata
      @options = options
    end

    def call
      return failure("Invalid charge category: #{@category}") unless ALLOWED_CATEGORIES.include?(@category)
      return failure("Charge amount must be greater than zero") unless @amount.positive?

      Folios::InsertTransaction.new(
        booking_folio: @folio,
        amount: @amount,
        transaction_type: "charge",
        category: @category,
        user: @user,
        description: @description,
        options: @options.merge(
          metadata: @metadata.merge(
            posting_source: "charge_service",
            charge_type: @category
          )
        )
      ).call
    end

    private

    def default_description
      @category.titleize
    end

    def success(transaction)
      OpenStruct.new(success?: true, transaction: transaction)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
