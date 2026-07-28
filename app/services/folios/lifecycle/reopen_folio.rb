# frozen_string_literal: true


module Folios
  module Lifecycle
    class ReopenFolio
      include Authorizable

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
          return failure("A folio with an AR invoice must be corrected through Accounts Receivable.") if @folio.ar_invoice.present?
          return failure("Reason is required to reopen an invoiced folio.") if @folio.invoice.present? && @reason.blank?

          @folio.reopening_for_correction do
            @folio.update!(status: "open", closed_at: nil, closed_by: nil)
            FolioInvoices::MarkUnderCorrection.call!(folio: @folio)
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
        actor_permits?(@user, PERMISSION, hotel: @hotel)
      end

      def success(folio)
        Folios::Lifecycle::Result.success(folio: folio)
      end

      def failure(error)
        Folios::Lifecycle::Result.failure(error, folio: @folio)
      end
    end
  end
end
