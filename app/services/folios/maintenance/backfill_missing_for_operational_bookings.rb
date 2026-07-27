# frozen_string_literal: true

module Folios
  module Maintenance
    class BackfillMissingForOperationalBookings
      Result = Struct.new(:created, :skipped, :failed, keyword_init: true)
      ELIGIBLE_STATUSES = %w[confirmed review_no_show checked_in review_due_out checkout_required no_show].freeze

      def self.call(scope: Booking.all)
        new(scope: scope).call
      end

      def initialize(scope:)
        @scope = scope
        @created = []
        @skipped = []
        @failed = []
      end

      def call
        eligible_bookings.find_each do |booking|
          if audit_running?(booking.hotel)
            @skipped << item_for(booking, "Night Audit is currently running.")
            next
          end

          begin
            existing_folio = booking.booking_folio
            folio = Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: nil)

            if existing_folio
              @skipped << item_for(booking, "Booking already has a folio.", folio_id: folio.id)
            else
              @created << item_for(booking, "Folio created.", folio_id: folio.id)
            end
          rescue StandardError => e
            @failed << item_for(booking, e.message)
          end
        end

        Result.new(created: @created, skipped: @skipped, failed: @failed)
      end

      private

      def eligible_bookings
        @scope.where(status: ELIGIBLE_STATUSES).includes(:hotel, :booking_folio)
      end

      def audit_running?(hotel)
        @audit_running_by_hotel_id ||= {}
        @audit_running_by_hotel_id.fetch(hotel.id) do
          @audit_running_by_hotel_id[hotel.id] = hotel.current_business_date_record&.audit_running? || false
        end
      end

      def item_for(booking, reason, folio_id: nil)
        {
          "booking_id" => booking.id,
          "confirmation_token" => booking.confirmation_token,
          "status" => booking.status,
          "folio_id" => folio_id,
          "reason" => reason
        }.compact
      end
    end
  end
end
