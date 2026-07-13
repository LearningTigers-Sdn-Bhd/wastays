# frozen_string_literal: true

module Reports
  class HousekeepingTasksPdfGenerator
    def initialize(hotel:, room_groups:, selected_date:)
      @hotel = hotel
      @room_groups = room_groups
      @selected_date = selected_date
    end

    def call
      pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [ 24, 24, 24, 24 ])

      logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
      if File.exist?(logo_path)
        pdf.image logo_path, at: [ pdf.bounds.right - 140, pdf.cursor + 8 ], width: 130
      end

      pdf.text "Housekeeping Tasks Report", size: 18, style: :bold
      pdf.move_down 4
      pdf.text @hotel.name.to_s, size: 11, style: :bold
      pdf.text "Generated: #{Time.zone.now.strftime('%d %b %Y %I:%M %p')}", size: 9
      pdf.move_down 16

      rows = [ [ "Room Number", "Room Type", "Assign To", "Room Status", "Arrival Time", "Arrival Date", "Departure", "Nights", "Task Details", "Task Status", "Remark" ] ]
      @room_groups.each do |group|
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

    private

    def helpers
      ApplicationController.helpers
    end
  end
end
