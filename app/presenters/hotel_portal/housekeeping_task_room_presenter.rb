# frozen_string_literal: true

module HotelPortal
  class HousekeepingTaskRoomPresenter
    attr_reader :room_number, :resolved_status, :active_booking, :room_type, :hotel

    def initialize(room_data, hotel)
      @room_number = room_data[:room_number]
      @resolved_status = room_data[:resolved_status]
      @active_booking = room_data[:active_booking]
      @room_type = room_data[:room_type]
      @hotel = hotel
      @raw_requests = room_data[:hk_requests]
    end

    # -- Room Status Presentation --

    def display_status
      resolved_status == "dirty" ? "Dirty" : resolved_status.humanize.titleize
    end

    def status_badge_class
      case resolved_status
      when "ready" then "bg-emerald-50 text-emerald-700 border-emerald-100"
      when "dirty" then "bg-amber-50 text-amber-700 border-amber-100"
      when "cleaning" then "bg-blue-50 text-blue-700 border-blue-100"
      when "occupied" then "bg-rose-50 text-rose-700 border-rose-100"
      else "bg-slate-50 text-slate-700 border-slate-100"
      end
    end

    # -- Booking Display --

    def guest_name
      active_booking&.guest_name
    end

    def arrival_time
      active_booking&.checked_in_at&.strftime("%I:%M %p") || "-"
    end

    def arrival_date
      active_booking ? helpers.display_housekeeping_date(active_booking.check_in) : "-"
    end

    def departure_date
      active_booking ? helpers.display_housekeeping_date(active_booking.check_out) : "-"
    end

    def nights
      active_booking ? active_booking.duration_in_nights : "-"
    end

    # -- Room Attribute Icons --

    def smoking_allowed?
      room_type&.smoking_allowed
    end

    def pets_allowed?
      room_type&.pets_allowed
    end

    # -- Task Requests --

    def task_requests
      @task_requests ||= @raw_requests.map { |req| TaskRequestPresenter.new(req, hotel) }
    end

    def first_task_request
      task_requests.first
    end

    private

    def helpers
      ApplicationController.helpers
    end

    # Wraps a single TASK_ROW to expose clean view methods for URL
    # routing, status resolution, and assignment logic.
    class TaskRequestPresenter
      attr_reader :request, :hotel

      delegate :id, :request_details, :status, :metadata, :created_at, to: :request

      def initialize(request, hotel)
        @request = request
        @hotel = hotel
      end

      def assignable?
        request&.id.present?
      end

      def checkout_request?
        request.respond_to?(:checkout_request?) && request.checkout_request?
      end

      def assign_url
        return unless assignable?

        if checkout_request?
          url_helpers.hotel_assign_checkout_request_path(hotel, request.id)
        else
          url_helpers.assign_hotel_housekeeping_task_path(hotel, request.id)
        end
      end

      def status_url
        return unless assignable?

        if checkout_request?
          url_helpers.hotel_checkout_request_status_path(hotel, request.id)
        else
          url_helpers.hotel_request_status_path(hotel, kind: "housekeeping", request_id: request.id)
        end
      end

      def assigned_to_value
        if request.respond_to?(:assigned_to_id)
          request.assigned_to_id.to_s.presence&.to_i
        else
          request.metadata&.dig("assigned_to").to_s.presence&.to_i
        end
      end

      def selected_status_value
        checkout_request? ? display_status_value : request.status
      end

      def display_status_value
        request.respond_to?(:display_status) ? request.display_status : request.status
      end

      def fallback_status_label
        if request.respond_to?(:display_status)
          request.display_status.to_s.humanize.titleize
        else
          request&.status.to_s.humanize.titleize.presence || "No Task"
        end
      end

      def has_details?
        request&.request_details.present? && request.request_details != "-"
      end

      private

      def url_helpers
        Rails.application.routes.url_helpers
      end
    end
  end
end
