# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ReservationCsvParser do
  let(:fixture) { Rails.root.join("spec/fixtures/files/ezee_reservation_csv_sample.csv") }
  let(:result) { described_class.call(path: fixture, filename: "export.csv") }

  def row(number) = result.rows.find { |candidate| candidate.reservation_number == number }

  it "reads every reservation and matches the footer's own count" do
    expect(result).to be_success
    expect(result.layout).to eq(:reservation_csv)
    expect(result.rows.size).to eq(result.declared_total)
    expect(result.warnings).to be_empty
  end

  it "does not read the footer totals row as a reservation" do
    expect(result.rows.map(&:reservation_number)).to all(match(/\ARES\d+(-\d+)?\z/))
  end

  it "reads by header name into the neutral row" do
    row = row("RES4433-1")

    expect(row).to have_attributes(
      layout: :reservation_csv, arrival: Date.new(2026, 9, 28), departure: Date.new(2026, 9, 30),
      nights: 2, adults: 2, children: 0, room_number: "C2", room_type: "Deluxe Room (Twin)",
      rate_type: "Publish Rate Malaysian", user: "MANDY", booking_status: "confirmed"
    )
  end

  it "makes the stay total the per-night rate times the nights" do
    expect(row("RES4433-1").total_amount).to eq(2200)
  end

  it "keeps the deposit as what was already paid, even when it exceeds the total" do
    expect(row("RES4433-2").amount_paid).to eq(8800)
  end

  it "ties the rooms of one booking together by the number before the suffix" do
    expect(result.rows.select { |r| r.group_ref == "RES4433" }.size).to eq(4)
    expect(row("RES4791").group_ref).to be_nil
  end

  it "maps the reservation type to a booking status" do
    expect(result.rows.map(&:booking_status).tally).to include("confirmed", "pending", "cancelled")
    released = result.rows.find { |r| r.booking_status == "cancelled" }
    expect(released).to be_present
  end

  describe "who the booking came from" do
    it "reads a Business Source company as the agency" do
      agent = result.rows.find { |r| r.agency_name.present? }

      expect(agent).to have_attributes(source: "Travel Agent", source_key: "travel_agent")
    end

    it "reads CTrip as an OTA channel, not an agency" do
      ota = result.rows.find { |r| r.source == "Trip.com" }

      expect(ota).to have_attributes(source_key: "ota", agency_name: nil)
    end

    it "reads Direct Booking as direct" do
      expect(row("RES4433-1")).to have_attributes(source: "Direct Booking", source_key: "direct", agency_name: nil)
    end

    it "treats a blank Business Source as internal and says so" do
      blank = result.rows.find { |r| r.source == "Unlabeled" }

      expect(blank).to have_attributes(source_key: "internal", agency_name: nil)
      expect(blank.internal_note).to include("Unlabeled agent booking")
    end
  end

  describe "guest names" do
    it "strips the honorific and keeps it in the staff note" do
      row = row("RES4433-1")

      expect(row.guest_name).to eq("GUEST A")
      expect(row.internal_note).to include("Title in eZee: Ms.")
    end

    it "trims a leading space" do
      expect(result.rows.map(&:guest_name)).to all(satisfy { |name| name == name.strip })
    end
  end

  describe "the boat" do
    it "is read from the reservation remarks, and the remark itself is kept" do
      row = result.rows.find { |r| r.remark.to_s.include?("BOAT IN : 1030 / BOAT OUT : 1130") }

      expect(row.boat_in).to eq(type: "provided", time: "10:30")
      expect(row.boat_out).to eq(type: "provided", time: "11:30")
      expect(row.remark).to include("BOAT IN : 1030")
    end

    it "reads a charter" do
      row = result.rows.find { |r| r.remark.to_s.include?("(CHARTER)") }

      expect(row.boat_in).to eq(type: "charter", time: "18:00")
    end
  end

  describe "the eZee balance" do
    it "notes a gap of RM10 a head as the jetty fee rather than charging it" do
      row = result.rows.find { |r| r.internal_note.to_s.include?("jetty fee") }

      expect(row).to be_present
      expect(row.internal_note).to include("not charged here")
    end
  end

  it "refuses a CSV that is missing a required column" do
    broken = Tempfile.new([ "broken", ".csv" ])
    broken.write("Res. No,Business Source\nRES1,X\n")
    broken.flush

    result = described_class.call(path: broken.path)

    expect(result).not_to be_success
    expect(result.error).to include("missing the columns", "Guest")
  end

  it "warns when the footer's count does not match what parsed" do
    tampered = Tempfile.new([ "tampered", ".csv" ])
    tampered.write(File.read(fixture).sub(/#\(\d+\)/, "#(999)"))
    tampered.flush

    result = described_class.call(path: tampered.path)

    expect(result.warnings.first).to include("states 999 reservations")
  end
end
