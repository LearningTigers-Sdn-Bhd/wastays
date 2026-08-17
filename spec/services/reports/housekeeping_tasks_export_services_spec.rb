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
      checked_out_at: nil,
      check_in: Time.zone.local(2026, 7, 21),
      check_out: Time.zone.local(2026, 7, 23),
      duration_in_nights: 2
    )
  end
  let(:housekeeper) { instance_double(User, name: "José 陈") }
  let(:room_groups) do
    [
      {
        room_type: instance_double(RoomType, name: "Ocean Suite"),
        rooms: [
          {
            room_number: "001",
            booking: booking,
            resolved_status: "dirty",
            pax: "2/1",
            notes: "=SUM(A1:A2) towels",
            assigned_to: housekeeper,
            booking_status_label: "Pending checkout",
            room_status_label: "Dirty"
          },
          {
            room_number: "002",
            booking: nil,
            resolved_status: "ready",
            pax: "—",
            notes: nil,
            assigned_to: nil,
            booking_status_label: "Vacant",
            room_status_label: "Cleaned"
          }
        ]
      }
    ]
  end

  it "maps the board into typed, reusable export rows" do
    table = Reports::HousekeepingTasksExportTable.new(room_groups: room_groups)

    expect(table.rows.first).to eq([
      "001", "Ocean Suite", "2/1", "Dirty", "José 陈", "Pending checkout",
      "21 Jul 2026, 02:30 PM", "23 Jul 2026, 12:00 AM", 2, "=SUM(A1:A2) towels"
    ])
    expect(table.rows.second).to eq([
      "002", "Ocean Suite", "—", "Cleaned", "Unassigned", "Vacant", "—", "—", nil, ""
    ])
    expect(table.room_count).to eq(2)
    expect(table.assigned_count).to eq(1)
  end

  it "generates safe CSV, genuine XLSX, and branded PDF output" do
    csv = Reports::HousekeepingTasksCsvGenerator.new(room_groups: room_groups).call
    xlsx = Reports::HousekeepingTasksExcelGenerator.new(
      hotel: hotel, room_groups: room_groups, selected_date: selected_date
    ).call
    pdf = Reports::HousekeepingTasksPdfGenerator.new(
      hotel: hotel, room_groups: room_groups, selected_date: selected_date, prepared_by: "Housekeeping Manager"
    ).call
    pdf_text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

    expect(csv).to start_with("\uFEFF")
    expect(csv).to include("'=SUM(A1:A2) towels")
    expect(csv).to include("002,Ocean Suite,—,Cleaned,Unassigned,Vacant,—,—,,")
    expect(xlsx).to start_with("PK")
    expect(Zip::File.open_buffer(StringIO.new(xlsx)).map(&:name)).to include("xl/workbook.xml")
    expect(pdf).to start_with("%PDF")
    expect(pdf_text).to include(
      "Housekeeping Tasks", "Selected date", "21 Jul 2026", "Prepared by", "Housekeeping Manager",
      "Rooms", "2", "José 陈", "002", "Vacant", "Confidential", "Page 1 of 1"
    )
  end
end
