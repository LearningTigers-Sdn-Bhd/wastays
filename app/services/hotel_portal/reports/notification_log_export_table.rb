# frozen_string_literal: true

module HotelPortal
  module Reports
    class NotificationLogExportTable
      HEADERS = [ "Time", "Booking Ref", "Guest", "Type", "Channel", "Status", "Trigger", "Error" ].freeze
      COLUMN_TYPES = %i[datetime text text text text text text text].freeze
      PDF_COLUMN_INDEXES = [ 0, 1, 2, 3, 4, 5, 7 ].freeze

      attr_reader :rows

      def initialize(logs:)
        @rows = logs.map do |log|
          [
            log.created_at,
            log.booking.confirmation_token,
            log.payload.to_h["guest_name"].presence || log.booking.guest_name,
            log.notification_type.to_s.humanize,
            log.channel.to_s.humanize,
            log.status.to_s.humanize,
            log.trigger_event.to_s.humanize,
            log.error_message.presence || "-"
          ]
        end
      end

      def record_count = rows.size
      def pdf_headers = PDF_COLUMN_INDEXES.map { |index| HEADERS[index] }
      def pdf_rows = rows.map { |row| PDF_COLUMN_INDEXES.map { |index| row[index] } }
    end
  end
end
