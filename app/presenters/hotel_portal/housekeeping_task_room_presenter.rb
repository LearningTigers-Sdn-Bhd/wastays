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

    def status_badge_variant
      ::Rooms::StatusPresentation.badge_variant(resolved_status)
    end

    # A task may only be completed once the room is actually being cleaned.
    def cleaning?
      resolved_status == "cleaning"
    end

    # -- Booking Display --

    def guest_name
      active_booking&.guest_name
    end

    # Date and time in one column. The timestamp is the real one when the guest
    # has actually arrived or left; otherwise the booked date is all there is.
    def arrival
      return "-" unless active_booking

      if active_booking.checked_in_at
        helpers.display_housekeeping_datetime(active_booking.checked_in_at)
      else
        helpers.display_housekeeping_date(active_booking.check_in)
      end
    end

    def departure
      return "-" unless active_booking

      if active_booking.checked_out_at
        helpers.display_housekeeping_datetime(active_booking.checked_out_at)
      else
        helpers.display_housekeeping_date(active_booking.check_out)
      end
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

    # Room numbers repeat across room types, so this is only unique within a
    # group -- which is how it is used, under the group's own key.
    def dom_key
      room_number.to_s.parameterize
    end

    # How many rows this room occupies -- the room columns rowspan across them.
    def row_span
      [ task_requests.size, 1 ].max
    end

    def label
      room_type ? "#{room_type.name} #{room_number}" : "Room #{room_number}"
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

      def assigned_to_name
        request.respond_to?(:assigned_to_name) ? request.assigned_to_name : "Unassigned"
      end

      def unassigned?
        assigned_to_value.blank?
      end

      def assigned?
        assigned_to_value.present?
      end

      def in_progress?
        display_status_value.to_s == "in_progress"
      end

      def held_by?(user)
        user.present? && assigned_to_value.present? && assigned_to_value == user.id
      end

      # What a performer may do to this task with a single button: claim it when
      # nobody holds it, hand it back when they hold it, nothing otherwise.
      # AssignStaff refuses the rest; this keeps the UI from offering it.
      def take_release_action(user)
        return unless assignable?
        return :take if unassigned?
        return :release if held_by?(user)

        nil
      end

      # Unique per task across the whole board, so ids and labels never collide.
      def dom_key
        "#{checkout_request? ? 'checkout' : 'housekeeping'}-#{id}"
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

      # Roughly what fits the two clamped lines of the task column. Past that the
      # text is cut off on screen, so it gets a tooltip carrying the whole note;
      # shorter notes are fully visible and a tooltip would only add hover noise.
      CLAMPED_LENGTH = 80

      def long_details?
        has_details? && request_details.to_s.length > CLAMPED_LENGTH
      end

      private

      def url_helpers
        Rails.application.routes.url_helpers
      end
    end
  end
end
