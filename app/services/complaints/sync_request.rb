require "ostruct"

module Complaints
  class SyncRequest
    def initialize(booking, event_payload)
      @booking = booking
      @data = event_payload[:data] || {}
      @complaint_details = normalize_complaint_details(
        event_payload[:complaint].presence || @data[:complaint].presence || @data[:message].presence
      )
      @requested_at = parse_requested_at(event_payload[:date].presence || @data[:date].presence)
      @external_id = event_payload[:external_id].presence || @data[:external_id].presence
      @status = event_payload[:status].presence || @data[:status].presence
    end

    def call
      return OpenStruct.new(success?: false, message: "Booking not found") unless @booking
      return OpenStruct.new(success?: false, message: "Complaint details are required") if @complaint_details.blank?

      complaint = if @external_id.present?
        @booking.complaint_requests.find_or_initialize_by(external_id: @external_id)
      else
        @booking.complaint_requests.build
      end
      complaint.assign_attributes(
        requested_at: @requested_at || complaint.requested_at || Time.current,
        complaint_details: @complaint_details,
        status: @status || complaint.status || "pending",
        metadata: complaint.metadata.to_h.merge(data: @data, external_id: @external_id).compact
      )
      complaint.save!

      OpenStruct.new(success?: true, complaint_request: complaint)
    rescue => e
      OpenStruct.new(success?: false, message: "Complaint sync failed: #{e.message}")
    end

    private

    def parse_requested_at(value)
      return Time.current if value.blank?

      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end

    def normalize_complaint_details(value)
      value.to_s.presence
    end
  end
end
