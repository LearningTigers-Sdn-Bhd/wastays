# frozen_string_literal: true

module Folios
  class PostInitialCharges
    def self.call(folio:, user:, options: {})
      new(folio: folio, user: user, options: options).call
    end

    def initialize(folio:, user:, options: {})
      @folio = folio
      @booking = folio.booking
      @user = user
      @options = options
    end

    def call
      FolioTransaction.transaction do
        post_accommodation_charges
        post_tax_charges
      end
    end

    private

    def post_accommodation_charges
      # Sum of booking_rooms subtotals
      amount = @booking.booking_rooms.sum(:subtotal)
      return if amount.zero?

      insert_transaction!(
        booking_folio: @folio,
        amount: amount,
        transaction_type: :charge,
        category: "accommodation",
        user: @user,
        description: "Room Charge (Base)",
        posting_date: @booking.check_in,
        options: @options
      )
    end

    def post_tax_charges
      @booking.tax_lines.each do |tax_line|
        amount = tax_line["amount"].to_d
        next if amount.zero?

        insert_transaction!(
          booking_folio: @folio,
          amount: amount,
          transaction_type: :charge,
          category: "tax",
          user: @user,
          description: "Tax: #{tax_line['name']}",
          posting_date: @booking.check_in,
          options: @options
        )
      end

      # Tourism tax if applicable
      if @booking.tourism_tax_amount.to_d > 0
        insert_transaction!(
          booking_folio: @folio,
          amount: @booking.tourism_tax_amount,
          transaction_type: :charge,
          category: "tax",
          user: @user,
          description: "Tourism Tax",
          posting_date: @booking.check_in,
          options: @options
        )
      end
    end

    def insert_transaction!(**attributes)
      result = Folios::InsertTransaction.new(**attributes).call
      raise "Failed to post initial folio charge: #{result.error}" unless result.success?

      result.transaction
    end
  end
end
