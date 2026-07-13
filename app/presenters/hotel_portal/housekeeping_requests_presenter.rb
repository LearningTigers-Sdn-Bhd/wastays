# frozen_string_literal: true

module HotelPortal
  class HousekeepingRequestsPresenter
    include ActionView::Helpers::TagHelper

    READONLY_INPUT_CLASS = "w-full rounded-xl border border-slate-200 bg-slate-50/50 px-4 py-3 " \
                           "text-sm font-medium text-slate-500 cursor-not-allowed shadow-sm focus:outline-none"

    attr_reader :room_number, :room_status, :housekeeping_requests

    def initialize(room_number:, room_status:, housekeeping_requests:)
      @room_number = room_number
      @room_status = room_status
      @housekeeping_requests = housekeeping_requests
    end

    def dnd_active?
      room_status&.active_dnd?
    end

    def requests?
      housekeeping_requests.any?
    end

    def request_rows
      @request_rows ||= housekeeping_requests.map { |req| RequestRow.new(req) }
    end

    def readonly_input_class
      READONLY_INPUT_CLASS
    end

    # Wraps a single HousekeepingRequest to expose clean view methods
    class RequestRow
      include ActionView::Helpers::TagHelper

      def initialize(request)
        @request = request
      end

      def details_present?
        @request.request_details.present?
      end

      def details
        @request.request_details
      end

      def humanized_status
        @request.status.humanize
      end

      def formatted_requested_at
        helpers.display_housekeeping_datetime(@request.display_requested_at)
      end

      def assigned_to_name
        @request.metadata&.dig("assigned_to_name").presence
      end

      def assignment_history
        @assignment_history ||= Array(@request.metadata&.dig("assignment_history")).filter_map do |event|
          AssignmentEvent.new(event)
        end
      end

      def assignment_history?
        assignment_history.any?
      end

      def readonly_input_class
        READONLY_INPUT_CLASS
      end

      private

      def helpers
        ApplicationController.helpers
      end
    end

    # Wraps a single assignment history hash entry
    class AssignmentEvent
      def initialize(event)
        @event = event
      end

      def assigned?
        name = @event["assigned_to_name"]
        name.present? && name != "Unassigned"
      end

      def assigned_to_name
        @event["assigned_to_name"]
      end

      def assigned_by_name
        @event["assigned_by_name"] || "System"
      end

      def formatted_timestamp
        helpers.display_housekeeping_datetime(DateTime.parse(@event["timestamp"]))
      rescue ArgumentError, TypeError
        @event["timestamp"]
      end

      private

      def helpers
        ApplicationController.helpers
      end
    end
  end
end
