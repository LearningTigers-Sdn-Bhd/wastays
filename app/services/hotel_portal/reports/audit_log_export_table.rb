# frozen_string_literal: true

module HotelPortal
  module Reports
    class AuditLogExportTable
      HEADERS = [ "Time", "User", "Action", "Details", "Value Change" ].freeze
      COLUMN_TYPES = %i[datetime text text text text].freeze

      attr_reader :rows

      def initialize(logs:)
        @rows = logs.map do |log|
          [ log.created_at, log.user.name, log.action_type.to_s.titleize, log.display_details, log.display_value_change ]
        end
      end

      def record_count = rows.size
    end
  end
end
