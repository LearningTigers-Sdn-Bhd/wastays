# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"
require "zip"

RSpec.describe "Housekeeping task export services" do
  let(:hotel) { build_stubbed(:hotel, name: "Andaman Hôtel 酒店") }
  let(:selected_date) { Date.new(2026, 7, 21) }
  let(:booking) do
    instance_double(
      Booking,
      checked_in_at: Time.zone.local(2026, 7, 21, 14, 30),
      check_in: Time.zone.local(2026, 7, 21),
      check_out: Time.zone.local(2026, 7, 23),
      duration_in_nights: 2
    )
  end
  let(:request) do
    HousekeepingTasks::TaskRow.new(
      id: 1,
      booking: booking,
      room_number: "001",
      request_details: "=SUM(A1:A2) towels",
      status: "in_progress",
      metadata: { "assigned_to_name" => "José 陈" },
      created_at: Time.zone.local(2026, 7, 21, 9),
      requested_at: Time.zone.local(2026, 7, 21, 9),
      source_kind: "housekeeping"
    )
  end
  let(:room_groups) do
    [
      {
        room_type: instance_double(RoomType, name: "Ocean Suite"),
        rooms: [
          {
            room_number: "001",
            resolved_status: "dirty",
            active_booking: booking,
            hk_requests: [ request ]
          }
        ]
      }
    ]
  end

  it "maps the board into typed, reusable export rows" do
    table = Reports::HousekeepingTasksExportTable.new(room_groups: room_groups)

    expect(table.rows.first).to eq([
      "001", "Ocean Suite", "José 陈", "Dirty", "02:30 PM", selected_date,
      Date.new(2026, 7, 23), 2, "=SUM(A1:A2) towels", "In Progress", ""
    ])
    expect(table.task_count).to eq(1)
  end

  it "generates safe CSV, genuine XLSX, and branded PDF output" do
    csv = Reports::HousekeepingTasksCsvGenerator.new(room_groups: room_groups).call
    xlsx = Reports::HousekeepingTasksExcelGenerator.new(
      hotel: hotel, room_groups: room_groups, selected_date: selected_date
    ).call
    pdf = Reports::HousekeepingTasksPdfGenerator.new(
      hotel: hotel, room_groups: room_groups, selected_date: selected_date
    ).call
    pdf_text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

    expect(csv).to start_with("\uFEFF")
    expect(csv).to include("'=SUM(A1:A2) towels")
    expect(xlsx).to start_with("PK")
    expect(Zip::File.open_buffer(StringIO.new(xlsx)).map(&:name)).to include("xl/workbook.xml")
    expect(pdf).to start_with("%PDF")
    expect(pdf_text).to include("HOUSEKEEPING TASKS", "José 陈", "Page 1 of 1")
  end
end
