# frozen_string_literal: true

require "ostruct"

module Folios
  class CloseFolio
    PERMISSION = "manage_folio_windows"

    def self.call(folio:, user:, reason: nil)
      new(folio: folio, user: user, reason: reason).call
    end

    def initialize(folio:, user:, reason: nil)
      @folio = folio
      @booking = folio.booking
      @hotel = folio.hotel
      @user = user
      @reason = reason.to_s.strip.presence
    end

    def call
      return failure("You do not have permission to manage folio windows.") unless permitted?

      @folio.with_lock do
        @folio.reload
        return failure("Folio is already closed.") if @folio.closed?
        return failure("Voided folios cannot be closed.") if @folio.voided?
        return failure("Cannot close a folio with pending upcoming charges.") if @folio.projected_forecasts.exists?

        balance = @folio.outstanding_balance.to_d
        return failure("Cannot close folio with non-zero balance of #{formatted_balance(balance)}.") unless balance.zero?

        @folio.update!(status: "closed", closed_at: Time.current, closed_by: @user)
        FolioOperationLog.create!(
          hotel: @hotel,
          booking: @booking,
          actor: @user,
          operation_type: "close_folio",
          source_folio: @folio,
          target_folio: @folio,
          amount: balance,
          currency: @folio.currency,
          reason: @reason,
          metadata: { closed_at: @folio.closed_at&.iso8601 }
        )
      end

      success(@folio)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def formatted_balance(balance)
      "#{@folio.currency} #{format('%.2f', balance)}"
    end

    def permitted?
      @user&.respond_to?(:superadmin?) && @user.superadmin? ||
        @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
    end

    def success(folio)
      OpenStruct.new(success?: true, folio: folio)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, folio: @folio)
    end
  end
end
