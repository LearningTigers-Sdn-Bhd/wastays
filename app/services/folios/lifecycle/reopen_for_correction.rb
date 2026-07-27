# frozen_string_literal: true


module Folios
  module Lifecycle
    class ReopenForCorrection
      include Authorizable

      PERMISSION = "post_folio_corrections".freeze

      def self.call(booking_folio:, user:, correction_reason:, correction_note:)
        new(
          booking_folio: booking_folio,
          user: user,
          correction_reason: correction_reason,
          correction_note: correction_note
        ).call
      end

      def initialize(booking_folio:, user:, correction_reason:, correction_note:)
        @booking_folio = booking_folio
        @user = user
        @correction_reason = correction_reason.to_s.strip
        @correction_note = correction_note.to_s.strip
      end

      def call
        return failure("A staff user is required to reopen a folio.") unless staff_user?
        return failure("You do not have permission to reopen this folio (#{PERMISSION}).") unless permitted?
        return failure("Correction reason can't be blank.") if @correction_reason.blank?
        return failure("Correction note can't be blank.") if @correction_note.blank?

        NightAudits::OperationalChangeGuard.call!(hotel: @booking_folio.hotel, action: :reopen_folio)

        BookingFolio.transaction do
          @booking_folio.with_lock do
            @booking_folio.reload
            return failure("Folio is already open.") if @booking_folio.open?

            invoice_number = @booking_folio.invoice_number

            @booking_folio.reopening_for_correction do
              @booking_folio.update!(status: "open")
              record_financial_audit_event!(invoice_number)

              success
            end
          end
        end
      rescue StandardError => e
        failure(e.message)
      end

      private

      def staff_user?
        @user.is_a?(User)
      end

      def permitted?
        actor_permits?(@user, PERMISSION, hotel: @booking_folio.hotel)
      end

      def record_financial_audit_event!(invoice_number)
        FinancialControls::AuditEventRecorder.call!(
          hotel: @booking_folio.hotel,
          business_date: @booking_folio.hotel.current_business_date,
          event_type: "folio_reopened_for_correction",
          source: "staff_correction",
          actor: @user,
          booking_folio: @booking_folio,
          booking: @booking_folio.booking,
          reason: @correction_reason,
          metadata: {
            correction_note: @correction_note,
            invoice_number: invoice_number,
            previous_status: "closed",
            new_status: "open",
            actor_id: @user.id,
            actor_type: @user.class.name
          }
        )
      end

      def success
        Folios::Lifecycle::Result.success(folio: @booking_folio)
      end

      def failure(error)
        Folios::Lifecycle::Result.failure(error, folio: @booking_folio)
      end
    end
  end
end
