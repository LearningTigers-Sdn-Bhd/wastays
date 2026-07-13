# frozen_string_literal: true

module Reports
  class HousekeepingTasksXlsGenerator
    def initialize(hotel:, room_groups:)
      @hotel = hotel
      @room_groups = room_groups
    end

    def call
      rows = []
      rows << xls_row([ "Room Number", "Room Type", "Assign To", "Room Status", "Arrival Time", "Arrival Date", "Departure", "Nights", "Task Details", "Task Status", "Remark" ])

      @room_groups.each do |group|
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

    private

    def xls_row(values)
      "<Row>#{values.map { |value| %(<Cell><Data ss:Type=\"String\">#{CGI.escapeHTML(value.to_s)}</Data></Cell>) }.join}</Row>"
    end

    def helpers
      ApplicationController.helpers
    end
  end
end
