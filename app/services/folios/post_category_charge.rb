# frozen_string_literal: true


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

      posting_date = @options[:posting_date] || @folio.hotel.current_business_date

      options = @options.merge(
        metadata: @metadata.merge(
          posting_source: "charge_service",
          charge_type: @category
        )
      )

      if @folio.hotel.date_closed?(posting_date) || posting_date < @folio.hotel.current_business_date
        options[:override_night_audit] = true
        options[:system_posting] = true
        options[:correction_reason] ||= "charge_on_closed_date"
        options[:correction_note] ||= "Automated posting of #{@category.titleize} on a closed business date."
      end

      Folios::InsertTransaction.new(
        booking_folio: @folio,
        amount: @amount,
        transaction_type: "charge",
        category: @category,
        user: @user,
        description: @description,
        posting_date: posting_date,
        options: options
      ).call
    end

    private

    def default_description
      @category.titleize
    end

    def success(transaction)
      Folios::TransactionResult.success(transaction: transaction)
    end

    def failure(error)
      Folios::TransactionResult.failure(error)
    end
  end
end
