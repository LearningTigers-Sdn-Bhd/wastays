# frozen_string_literal: true

module Folios
  module Lifecycle
    class ReopenNoShowFoliosForReinstatement
      def self.call(booking:, user:)
        new(booking: booking, user: user).call
      end

      def initialize(booking:, user:)
        @booking = booking
        @user = user
      end

      def call
        lifecycle_closed_folios.each do |folio|
          folio.lock!
          folio.reload
          next unless folio.closed?

          folio.reopening_for_correction do
            folio.update!(status: "open", closed_at: nil, closed_by: nil)
            FolioOperationLog.create!(
              hotel: folio.hotel,
              booking: @booking,
              actor: @user,
              operation_type: "reopen_folio",
              source_folio: folio,
              target_folio: folio,
              currency: folio.currency,
              reason: "No-show booking reinstated.",
              metadata: {
                source: "no_show_reinstatement",
                reopened_at: Time.current.iso8601
              }
            )
          end
        end
      end

      private

      def lifecycle_closed_folios
        closed_folio_ids = FolioOperationLog
          .where(booking: @booking, operation_type: "close_folio")
          .where("metadata->>'source' = ?", CloseNoShowFolios::CLOSE_SOURCE)
          .pluck(:source_folio_id)

        @booking.booking_folios.where(id: closed_folio_ids, status: "closed")
      end
    end
  end
end
