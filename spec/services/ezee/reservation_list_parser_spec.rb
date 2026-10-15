# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ReservationListParser do
  let(:fixture) { Rails.root.join("spec/fixtures/files/ezee_reservation_list_sample.xls") }

  def call(path: fixture, filename: "Reservation List.xls")
    described_class.call(path: path, filename: filename)
  end

  it "reads every reservation row on the real export, matching its own declared total" do
    result = call

    expect(result).to be_success
    expect(result.rows.size).to eq(result.declared_total)
    expect(result.warnings).to be_empty
  end

  it "parses a row's merged-cell columns into the row struct" do
    row = call.rows.first

    expect(row.reservation_number).to eq("412301")
    expect(row.source).to eq("Travel Agent")
    expect(row.guest_name).to eq("BORNEO TRAILS TOURS & TRAVEL SDN BHD")
    expect(row.arrival).to eq(Date.new(2026, 10, 3))
    expect(row.departure).to eq(Date.new(2026, 10, 4))
    expect(row.room_number).to eq("K2")
    expect(row.room_type).to eq("DLX")
    expect(row.total_amount).to eq(365.0)
    expect(row.remark).to be_present
  end

  it "refuses a file extension it does not handle" do
    result = call(path: fixture, filename: "notes.pdf")

    expect(result).not_to be_success
    expect(result.error).to include("Upload a .xls, .xlsx or .csv export")
    expect(result.rows).to eq([])
  end

  it "reports a file it cannot read as such, rather than raising" do
    not_a_spreadsheet = Rails.root.join("spec/fixtures/files/sample_image.jpg")

    result = call(path: not_a_spreadsheet, filename: "Reservation List.xls")

    expect(result).not_to be_success
    expect(result.error).to include("Could not read the file")
  end

  it "reads to the last row instead of stopping at the first blank one" do
    # ~69% of the report's rows are blank spacer rows between reservations --
    # the fixture's own declared total, matched above, is the guard against a
    # parser that gave up early.
    result = call

    expect(result.rows.last.reservation_number).to be_present
  end
end
