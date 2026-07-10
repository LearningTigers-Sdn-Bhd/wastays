# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "cgi"

module HotelPortal
  class HousekeepingTasksController < BaseController
    HOUSEKEEPING_REQUEST_EXCLUDED_STATUSES = %w[pending completed failed cancelled].freeze
    TASK_ROW = Struct.new(
      :id,
      :booking,
      :room_number,
      :request_details,
      :status,
      :metadata,
      :created_at,
      :requested_at,
      :source_kind,
      keyword_init: true
    ) do
      def checkout_request?
        source_kind == "checkout"
      end

      def assigned_to_id
        metadata.to_h["assigned_to"]
      end

      def assigned_to_name
        metadata.to_h["assigned_to_name"].presence || "Unassigned"
      end

      def display_status
        return status unless checkout_request?

        metadata.to_h["workflow_status"].presence ||
          HotelPortal::HousekeepingTasksController.checkout_workflow_status_for(status)
      end
    end

    def self.checkout_workflow_status_for(status)
      case status.to_s
      when "pending" then "new"
      when "acknowledged" then "assigned"
      when "completed" then "completed"
      when "cancelled" then "no_task"
      else "new"
      end
    end

    before_action :authorize_manage_housekeeping_tasks!
    before_action -> { require_feature!("task_assignment_minibar_log") }

    def index
      @staff_members = User.where(id: UserHotelAccess.active
                                                     .where(hotel_id: current_hotel.id)
                                                     .joins(:role)
                                                     .where(roles: { slug: "housekeeper" })
                                                     .select(:user_id))
                           .order(:name)

      # Determine selected date, defaulting to Date.current
      @selected_date = Date.current
      if params[:date].present?
        begin
          @selected_date = Date.parse(params[:date].to_s)
        rescue ArgumentError, TypeError
          # fallback to Date.current
        end
      end

      # Build room groups with resolved statuses, active bookings, and tasks for the selected date
      @room_groups = current_hotel.room_types.order(:name).map do |room_type|
        rooms_list = room_type.room_numbers.map do |room_number|
          resolved = Rooms::StatusResolver.new(
            hotel: current_hotel,
            room_type: room_type,
            room_number: room_number,
            date: @selected_date
          ).call

          active_booking = resolved.booking_details&.dig(:active)&.first || resolved.booking_details&.dig(:completed)&.first

          hk_requests = housekeeping_requests_for_room(room_number)

          real_requests = hk_requests.reject { |r| r.status == "no_task" }
          if real_requests.any?
            hk_requests = real_requests
          elsif hk_requests.empty?
            hk_requests = [
              TASK_ROW.new(
                id: nil,
                booking: active_booking,
                room_number: room_number,
                request_details: "-",
                status: "no_task",
                metadata: {},
                created_at: @selected_date.beginning_of_day,
                requested_at: @selected_date.beginning_of_day,
                source_kind: "housekeeping"
              )
            ]
          end

          {
            room_number: room_number,
            room_type: room_type,
            resolved_status: resolved.status,
            active_booking: active_booking,
            hk_requests: hk_requests
          }
        end

        {
          room_type: room_type,
          rooms: rooms_list
        }
      end

      # Filter by assignment
      if params[:assigned_to].present?
        assigned_to_id = params[:assigned_to].to_i
        @room_groups.each do |group|
          group[:rooms].select! do |r|
            r[:hk_requests].any? { |req| req.metadata&.dig("assigned_to") == assigned_to_id }
          end
        end
        @room_groups.select! { |group| group[:rooms].any? }
      end

      # Filter by room status
      if params[:room_status].present?
        status_val = params[:room_status].to_s
        @room_groups.each do |group|
          group[:rooms].select! { |r| r[:resolved_status] == status_val }
        end
        @room_groups.select! { |group| group[:rooms].any? }
      end

      # Filter by search query
      if params[:q].present?
        q = params[:q].downcase
        @room_groups.each do |group|
          group[:rooms].select! do |r|
            r[:room_number].to_s.downcase.include?(q) ||
              group[:room_type].name.downcase.include?(q) ||
              (r[:active_booking] && (r[:active_booking].guest_name.to_s.downcase.include?(q) || r[:active_booking].confirmation_token.to_s.downcase.include?(q))) ||
              (r[:hk_requests] && r[:hk_requests].any? { |hk| hk.request_details.to_s.downcase.include?(q) })
          end
        end
        @room_groups.select! { |group| group[:rooms].any? }
      end

      respond_to do |format|
        format.html
        format.pdf do
          send_data generate_pdf(@room_groups),
            filename: "housekeeping-tasks-#{@selected_date}.pdf",
            type: "application/pdf"
        end
        format.xls do
          send_data generate_xls(@room_groups),
            filename: "housekeeping-tasks-#{@selected_date}.xls",
            type: "application/vnd.ms-excel"
        end
      end
    end

    def assign
      @request = HousekeepingRequest.left_joins(:booking)
                                    .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: current_hotel.id)
                                    .find(params[:id])

      assigned_to = params[:assigned_to].presence

      # Resolve room number, falling back to the booking's rooms if the request doesn't have it directly
      room_number = @request.room_number.presence
      room_number ||= @request.booking&.booking_rooms&.where.not(room_number: [ nil, "" ])&.first&.room_number.presence

      active_requests = []
      if room_number.present?
        active_requests = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                             .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: current_hotel.id)
                                             .where(
                                               "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                               room_number: room_number
                                             )
                                             .where.not(status: %w[pending completed failed cancelled])
                                             .distinct
                                             .to_a
      end

      if active_requests.empty?
        active_requests = [ @request ]
      end

      # Reject any placeholder "no_task" requests if there are other active real requests
      real_active = active_requests.reject { |r| r.status == "no_task" }
      if real_active.any?
        active_requests = real_active
      end

      active_requests.each do |req|
        req_metadata = req.metadata.to_h
        req_status = req.status

        if assigned_to
          staff = User.where(id: UserHotelAccess.active
                                                 .where(hotel_id: current_hotel.id)
                                                 .joins(:role)
                                                 .where(roles: { slug: "housekeeper" })
                                                 .select(:user_id))
                      .find_by(id: assigned_to)
          if staff
            if req_metadata["assigned_to"] != staff.id
              history = Array(req_metadata["assignment_history"])
              history << {
                "assigned_to_id" => staff.id,
                "assigned_to_name" => staff.name,
                "assigned_by_id" => current_user.id,
                "assigned_by_name" => current_user.name,
                "timestamp" => Time.current.iso8601
              }
              req_metadata["assignment_history"] = history
            end
            req_metadata["assigned_to"] = staff.id
            req_metadata["assigned_to_name"] = staff.name
            if req_status.in?(%w[new no_task])
              req_status = "assigned"
            end
          else
            if req_metadata["assigned_to"].present?
              history = Array(req_metadata["assignment_history"])
              history << {
                "assigned_to_name" => "Unassigned",
                "assigned_by_id" => current_user.id,
                "assigned_by_name" => current_user.name,
                "timestamp" => Time.current.iso8601
              }
              req_metadata["assignment_history"] = history
            end
            req_metadata.delete("assigned_to")
            req_metadata.delete("assigned_to_name")
            if req_status == "assigned"
              req_status = "new"
            end
          end
        else
          if req_metadata["assigned_to"].present?
            history = Array(req_metadata["assignment_history"])
            history << {
              "assigned_to_name" => "Unassigned",
              "assigned_by_id" => current_user.id,
              "assigned_by_name" => current_user.name,
              "timestamp" => Time.current.iso8601
            }
            req_metadata["assignment_history"] = history
          end
          req_metadata.delete("assigned_to")
          req_metadata.delete("assigned_to_name")
          if req_status == "assigned"
            req_status = "new"
          end
        end

        req.update!(metadata: req_metadata, status: req_status)
      end

      respond_to do |format|
        format.html { redirect_to hotel_housekeeping_tasks_path(current_hotel), notice: "Task assigned successfully." }
        format.json { render json: { ok: true } }
      end
    end

    private

    def housekeeping_requests_for_room(room_number)
      room_number = room_number.to_s
      requests = []

      # Load housekeeping requests tied to this room.
      HousekeepingRequest.where(hotel_id: current_hotel.id, room_number: room_number).find_each do |request|
        next if request.status.in?(HOUSEKEEPING_REQUEST_EXCLUDED_STATUSES)
        next if checkout_cleaning_housekeeping_request?(request)

        requests << task_row_from_housekeeping_request(request)
      end

      hotel_bookings_with_requests.each do |booking|
        room_matches = booking.booking_rooms.any? { |booking_room| booking_room.room_number.to_s == room_number }
        next unless room_matches

        booking.housekeeping_requests.each do |request|
          next if request.room_number.present? && request.room_number.to_s != room_number
          next if request.status.in?(HOUSEKEEPING_REQUEST_EXCLUDED_STATUSES)
          next if checkout_cleaning_housekeeping_request?(request)

          requests << task_row_from_housekeeping_request(request)
        end

        booking.check_out_requests.each do |request|
          next unless request.status.in?(%w[new assigned in_progress pending acknowledged])

          checkout_room_number = request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number
          next unless checkout_room_number.to_s == room_number

          requests << task_row_from_checkout_request(request, booking, checkout_room_number)
        end
      end

      requests.uniq { |request| [ request.respond_to?(:source_kind) ? request.source_kind : "housekeeping", request.id ] }
              .sort_by { |request| [ request.status == "no_task" ? 1 : 0, -request.created_at.to_i ] }
    end

    def hotel_bookings_with_requests
      @hotel_bookings_with_requests ||= current_hotel.bookings.includes(:housekeeping_requests, :check_out_requests, :booking_rooms).to_a
    end

    def task_row_from_housekeeping_request(request)
      TASK_ROW.new(
        id: request.id,
        booking: request.booking,
        room_number: request.room_number,
        request_details: request.request_details,
        status: request.status,
        metadata: request.metadata.to_h,
        created_at: request.created_at,
        requested_at: request.requested_at || request.created_at,
        source_kind: "housekeeping"
      )
    end

    def task_row_from_checkout_request(request, booking, room_number)
      TASK_ROW.new(
        id: request.id,
        booking: booking,
        room_number: room_number,
        request_details: request.guest_notes.presence || "Checkout Room Cleaning",
        status: request.status,
        metadata: request.metadata.to_h.merge("workflow_status" => request.metadata.to_h["workflow_status"].presence || self.class.checkout_workflow_status_for(request.status)),
        created_at: request.created_at,
        requested_at: request.requested_at,
        source_kind: "checkout"
      )
    end

    def checkout_cleaning_housekeeping_request?(request)
      request.metadata&.dig("checkout_request_id").present? || request.request_details.to_s.strip == "Checkout Room Cleaning"
    end

    def authorize_manage_housekeeping_tasks!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_housekeeping_tasks", hotel: current_hotel)
    end

    def generate_pdf(room_groups)
      pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [ 24, 24, 24, 24 ])

      logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
      if File.exist?(logo_path)
        pdf.image logo_path, at: [ pdf.bounds.right - 140, pdf.cursor + 8 ], width: 130
      end

      pdf.text "Housekeeping Tasks Report", size: 18, style: :bold
      pdf.move_down 4
      pdf.text current_hotel.name.to_s, size: 11, style: :bold
      pdf.text "Generated: #{Time.zone.now.strftime('%d %b %Y %I:%M %p')}", size: 9
      pdf.move_down 16

      rows = [ [ "Room Number", "Room Type", "Assign To", "Room Status", "Arrival Time", "Arrival Date", "Departure", "Nights", "Task Details", "Task Status", "Remark" ] ]
      room_groups.each do |group|
        group[:rooms].each do |room|
          active_booking = room[:active_booking]
          room[:hk_requests].each do |req|
            rows << [
              room[:room_number].to_s,
              group[:room_type].name.to_s,
              req.metadata&.dig("assigned_to_name").presence || "Unassigned",
              room[:resolved_status].to_s.humanize.titleize,
              (active_booking && active_booking.checked_in_at&.strftime("%I:%M %p")) || "-",
              active_booking ? helpers.display_housekeeping_date(active_booking.check_in) : "-",
              active_booking ? helpers.display_housekeeping_date(active_booking.check_out) : "-",
              active_booking ? active_booking.duration_in_nights.to_s : "-",
              req.request_details.to_s,
              req.status.to_s.humanize.titleize,
              "" # Remark
            ]
          end
        end
      end

      pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 7, padding: [ 4, 4, 4, 4 ] }) do
        row(0).font_style = :bold
        row(0).background_color = "F1F5F9"
      end

      pdf.render
    end

    def generate_xls(room_groups)
      rows = []
      rows << xls_row([ "Room Number", "Room Type", "Assign To", "Room Status", "Arrival Time", "Arrival Date", "Departure", "Nights", "Task Details", "Task Status", "Remark" ])

      room_groups.each do |group|
        group[:rooms].each do |room|
          active_booking = room[:active_booking]
          room[:hk_requests].each do |req|
            rows << xls_row([
              room[:room_number].to_s,
              group[:room_type].name.to_s,
              req.metadata&.dig("assigned_to_name").presence || "Unassigned",
              room[:resolved_status].to_s.humanize.titleize,
              (active_booking && active_booking.checked_in_at&.strftime("%I:%M %p")) || "-",
              active_booking ? helpers.display_housekeeping_date(active_booking.check_in) : "-",
              active_booking ? helpers.display_housekeeping_date(active_booking.check_out) : "-",
              active_booking ? active_booking.duration_in_nights.to_s : "-",
              req.request_details.to_s,
              req.status.to_s.humanize.titleize,
              "" # Remark
            ])
          end
        end
      end

      <<~XML
        <?xml version="1.0"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
          <Worksheet ss:Name="Housekeeping Tasks">
            <Table>
              #{rows.join("\n")}
            </Table>
          </Worksheet>
        </Workbook>
      XML
    end

    def xls_row(values)
      "<Row>#{values.map { |value| %(<Cell><Data ss:Type=\"String\">#{CGI.escapeHTML(value.to_s)}</Data></Cell>) }.join}</Row>"
    end
  end
end
