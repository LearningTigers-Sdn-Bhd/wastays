# frozen_string_literal: true

module HotelPortal
  class RequestsArchive
    include Rails.application.routes.url_helpers

    attr_reader :hotel, :params

    def initialize(hotel, params = {})
      @hotel = hotel
      @params = params || {}
    end

    def rows
      @rows ||= filtered_rows
    end

    def summary_counts
      {
        archived: rows.count { |row| row[:archived_at].present? }
      }
    end

    private

    def filtered_rows
      rows = build_rows.select { |row| row[:archived_at].present? }
      rows = rows.select { |row| search_match?(row) }
      rows = rows.select { |row| kind_match?(row) }
      rows = rows.select { |row| status_match?(row) }
      rows = rows.select { |row| date_range_match?(row) }
      rows.sort_by { |row| row[:requested_at] || Time.zone.at(0) }.reverse
    end

    def build_rows
      rows = []

      hotel.bookings.includes(:housekeeping_requests, :complaint_requests).find_each do |booking|
        booking.housekeeping_requests.each do |request|
          rows << build_row(
            kind: "housekeeping",
            request: request,
            booking: booking,
            title: request.request_details
          )
        end

        booking.complaint_requests.each do |request|
          rows << build_row(
            kind: "complaint",
            request: request,
            booking: booking,
            title: request.complaint_details
          )
        end
      end

      rows
    end

    def build_row(kind:, request:, booking:, title:)
      {
        kind: kind,
        request_id: request.id,
        booking_id: booking.id,
        booking_token: booking.confirmation_token,
        guest_name: booking.guest_name,
        title: title,
        requested_at: request.display_requested_at,
        completed_at: request.completed_at,
        status: request.status,
        internal_notes: request.internal_notes_list,
        archived_at: request.archived_at,
        status_class: status_class_for(kind, request.status),
        kind_class: kind_class_for(kind),
        archive_url: request.archived? ? hotel_unarchive_request_path(hotel, kind: kind, request_id: request.id) : hotel_archive_request_path(hotel, kind: kind, request_id: request.id),
        archive_action: request.archived? ? "Unarchive" : "Archive",
        booking_url: hotel_booking_path(hotel, booking, tab: "requests")
      }
    end

    def search_match?(row)
      query = params[:q].to_s.strip.downcase
      return true if query.blank?

      # Map query to potential statuses if it matches a group name
      status_aliases = []
      if "pending".include?(query)
        status_aliases += %w[pending in_progress failed]
      end
      if "completed".include?(query) || "resolved".include?(query)
        status_aliases += %w[completed resolved]
      end
      if "cancelled".include?(query)
        status_aliases << "cancelled"
      end

      searchable_values = [
        row[:guest_name],
        row[:booking_token],
        row[:title],
        row[:status],
        row[:kind]
      ]

      # Check if query matches any searchable value OR if the row status matches a status alias
      searchable_values.compact.any? { |value| value.to_s.downcase.include?(query) } ||
        status_aliases.include?(row[:status].to_s) ||
        row[:internal_notes].any? { |n| n["body"].to_s.downcase.include?(query) }
    end

    def kind_match?(row)
      kind = params[:kind].to_s
      return true if kind.blank? || kind == "all"

      row[:kind] == kind
    end

    def status_match?(row)
      status = params[:status].to_s
      return true if status.blank? || status == "all"

      case status
      when "pending"
        row[:status].in?(%w[pending in_progress failed])
      when "completed"
        row[:status].in?(%w[completed resolved])
      when "cancelled"
        row[:status] == "cancelled"
      else
        true
      end
    end

    def date_range_match?(row)
      date = params[:date].presence || params[:requested_on].presence
      return true if date.blank?

      requested_at = row[:requested_at]
      return false if requested_at.blank?

      selected_date = begin
        Date.parse(date.to_s)
      rescue ArgumentError, TypeError
        nil
      end
      return true if selected_date.blank?

      requested_at.to_date == selected_date
    end

    def status_class_for(kind, status)
      case kind.to_s
      when "housekeeping"
        case status.to_s
        when "completed", "resolved" then "bg-green-50 text-green-700 border border-green-100"
        when "cancel", "rejected" then "bg-red-50 text-red-700 border border-red-100"
        when "pending", "requested" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
        else "bg-gray-50 text-gray-700 border border-gray-100"
        end
      else
        case status.to_s
        when "resolved", "completed" then "bg-green-50 text-green-700 border border-green-100"
        when "in_progress" then "bg-blue-50 text-blue-700 border border-blue-100"
        when "failed", "cancelled" then "bg-red-50 text-red-700 border border-red-100"
        when "pending" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
        else "bg-gray-50 text-gray-700 border border-gray-100"
        end
      end
    end

    def kind_class_for(kind)
      kind == "housekeeping" ? "bg-blue-50 text-blue-600 border-blue-100" : "bg-rose-50 text-rose-600 border-rose-100"
    end
  end
end
