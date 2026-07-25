# frozen_string_literal: true

require "ostruct"

module Folios
  class ReopenFolio
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
        return failure("Only closed folios can be reopened.") unless @folio.closed?

        @folio.reopening_for_correction do
          @folio.update!(status: "open", closed_at: nil, closed_by: nil)
          FolioOperationLog.create!(
            hotel: @hotel,
            booking: @booking,
            actor: @user,
            operation_type: "reopen_folio",
            source_folio: @folio,
            target_folio: @folio,
            currency: @folio.currency,
            reason: @reason,
            metadata: { reopened_at: Time.current.iso8601 }
          )
        end
      end

      success(@folio)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

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
