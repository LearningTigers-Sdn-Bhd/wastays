require "ostruct"

module Housekeeping
  class SyncRequestEvent
    def initialize(booking, event_payload)
      @booking = booking
      @data = event_payload[:data] || {}
      @external_id = event_payload[:external_id].presence || @data[:external_id].presence
      @request_details = normalize_request_details(
        event_payload[:requests].presence || @data[:requests].presence || @data[:message].presence
      )
      @requested_at = parse_requested_at(event_payload[:date].presence || @data[:date].presence)
      @status = normalize_status(event_payload[:status].presence || @data[:status].presence)
    end

    def call
      return OpenStruct.new(success?: false, message: "Booking not found") unless @booking

      request = nil
      ActiveRecord::Base.transaction do
        request = find_or_build_request
        request_details = @request_details.presence || request.request_details
        request.assign_attributes(
          requested_at: @requested_at || request.requested_at || Time.current,
          request_details: request_details,
          status: resolved_status(request),
          metadata: merged_metadata(request),
          external_id: @external_id.presence || request.external_id
        )

        request.completed_at = request.status == "completed" ? (request.completed_at || Time.current) : nil
        request.save!
      end

      OpenStruct.new(success?: true, housekeeping_request: request)
    rescue => e
      OpenStruct.new(success?: false, message: "Housekeeping sync failed: #{e.message}")
    end

    private

    def resolved_status(request)
      return @status if HousekeepingRequest::STATUSES.include?(@status)

      request.status.presence || "pending"
    end

    def find_or_build_request
      if @external_id.present?
        @booking.housekeeping_requests.find_or_initialize_by(external_id: @external_id)
      else
        @booking.housekeeping_requests.order(created_at: :desc).first || @booking.housekeeping_requests.build
      end
    end

    def merged_metadata(request)
      request.metadata.to_h.merge(data: @data).compact
    end

    def normalize_status(value)
      value = value.to_s
      return value if HousekeepingRequest::STATUSES.include?(value)

      "pending"
    end

    def parse_requested_at(value)
      return Time.current if value.blank?

      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end

    def normalize_request_details(value)
      return value.join(", ") if value.is_a?(Array)

      value.to_s.presence
    end
  end
end
