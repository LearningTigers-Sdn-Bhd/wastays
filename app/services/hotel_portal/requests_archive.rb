# frozen_string_literal: true

module HotelPortal
  class RequestsArchive
    include Rails.application.routes.url_helpers
    include Requests::Narrowing

    attr_reader :hotel, :params

    def initialize(hotel, params = {})
      @hotel = hotel
      @params = params || {}
    end

    # The archive is read by when a request was put away, which is the only date
    # a row here has that a reader is looking for.
    def date_window
      @date_window ||= Requests::DateWindow.new(
        hotel: hotel,
        anchor_date: params[:date],
        days: params[:days]
      )
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
      build_rows.sort_by { |row| row[:requested_at] || Time.zone.at(0) }.reverse
    end

    # The archive is only ever the archived, so only the archived is asked for.
    # A request reaches its booking rather than the other way around, which keeps
    # a hotel's whole history of requests out of a page showing a page of them.
    def build_rows
      rows = []

      archived_housekeeping_requests.each do |request|
        rows << build_row(
          kind: "housekeeping",
          request: request,
          booking: request.booking,
          title: request.request_details
        )
      end

      archived_complaint_requests.each do |request|
        rows << build_row(
          kind: "complaint",
          request: request,
          booking: request.booking,
          title: request.complaint_details
        )
      end

      archived_checkout_requests.each do |request|
        booking = request.booking
        archived_at = request.metadata.to_h["archived_at"]

        rows << {
          kind: "checkout",
          request_id: request.id,
          booking_id: booking.id,
          booking_token: booking.confirmation_token,
          guest_name: booking.guest_name,
          title: request.guest_notes.presence || "Checkout requested",
          requested_at: request.requested_at,
          completed_at: request.acknowledged_at || request.updated_at,
          status: request.status,
          internal_notes: [],
          archived_at: archived_at.presence || request.updated_at,
          status_class: status_class_for("checkout", request.status),
          kind_class: kind_class_for("checkout"),
          archive_url: hotel_unarchive_request_path(hotel, kind: "checkout", request_id: request.id),
          archive_action: "Unarchive",
          booking_url: hotel_booking_path(hotel, booking, tab: "requests")
        }
      end

      rows
    end

    def hotel_booking_ids
      @hotel_booking_ids ||= hotel.bookings.select(:id)
    end

    def window_range
      @window_range ||= date_window.range
    end

    # A kind the filter bar ruled out is a query not worth making.
    def wanted_kind?(kind)
      wanted = params[:kind].to_s
      wanted.blank? || wanted == "all" || wanted == kind
    end

    def archived_housekeeping_requests
      return HousekeepingRequest.none unless wanted_kind?("housekeeping")

      narrow(HousekeepingRequest.in_hotel(hotel).archived, kind: "housekeeping")
        .where.not(booking_id: nil)
        .where(archived_at: window_range)
        .includes(:booking)
        .order(requested_at: :desc)
    end

    def archived_complaint_requests
      return ComplaintRequest.none unless wanted_kind?("complaint")

      narrow(ComplaintRequest.where(booking_id: hotel_booking_ids).archived, kind: "complaint")
        .where(archived_at: window_range)
        .includes(:booking)
        .order(requested_at: :desc)
    end

    # A checkout carries no archived_at column: cancelling is an ending of its
    # own, and completing is archived by a note in its metadata. Neither is a
    # column the window can be read against, so when the record was last written
    # stands in for when it was put away -- which is what putting it away did.
    def archived_checkout_requests
      return CheckOutRequest.none unless wanted_kind?("checkout")

      narrow(CheckOutRequest.where(booking_id: hotel_booking_ids), kind: "checkout")
        .where(
          "check_out_requests.status = 'cancelled' OR " \
          "(check_out_requests.status = 'completed' AND COALESCE(check_out_requests.metadata->>'archived_at', '') <> '')"
        )
        .where(updated_at: window_range)
        .includes(:booking)
        .order(requested_at: :desc)
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
        booking_url: hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
      }
    end

    # The archive is where notes are read, so it is where they are searched.
    def search_internal_notes?
      true
    end

    def status_class_for(kind, status)
      case kind.to_s
      when "housekeeping", "checkout"
        case status.to_s
        when "completed", "resolved" then "bg-green-50 text-green-700 border border-green-100"
        when "cancel", "rejected", "cancelled" then "bg-red-50 text-red-700 border border-red-100"
        when "pending", "requested" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
        else "bg-muted text-foreground border border-border"
        end
      else
        case status.to_s
        when "resolved", "completed" then "bg-green-50 text-green-700 border border-green-100"
        when "in_progress" then "bg-blue-50 text-blue-700 border border-blue-100"
        when "failed", "cancelled" then "bg-red-50 text-red-700 border border-red-100"
        when "pending" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
        else "bg-muted text-foreground border border-border"
        end
      end
    end

    def kind_class_for(kind)
      if kind == "housekeeping"
        "bg-blue-50 text-blue-600 border-blue-100"
      elsif kind == "checkout"
        "bg-amber-50 text-amber-600 border-amber-100"
      else
        "bg-rose-50 text-rose-600 border-rose-100"
      end
    end
  end
end
