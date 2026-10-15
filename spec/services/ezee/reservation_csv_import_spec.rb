# frozen_string_literal: true

require "rails_helper"

# The reservation CSV end to end: parse, resolve against a per-person hotel,
# and create. eZee has no per-person model, so its export reads like a per-room
# price; the hotel here sells per person.
RSpec.describe "Importing the eZee reservation CSV" do
  include ActiveSupport::Testing::TimeHelpers

  ROOMS = {
    "Deluxe Twin" => %w[C2 C4 C6 F1 F2 F3 F4],
    "Deluxe King" => %w[A2 A4 A6 A8 A10 C1 C3 C5 C7],
    "Deluxe Super King" => %w[A1 A3 A5 A7 A9],
    "Standard Twin" => %w[B1 B2 B3 B4 B5 B6 B7 B8 B9 B10],
    "Standard Family" => %w[D1 D2 D3 D4 D5 D6],
    "Standard Triple" => %w[E1 E2 E3 E4]
  }.freeze

  let(:fixture) { Rails.root.join("spec/fixtures/files/ezee_reservation_csv_sample.csv") }
  let(:hotel) { create(:hotel, :per_person, status: "live", country: "Malaysia") }
  let(:user) { create(:user, account: hotel.account, name: "Importer") }
  let(:import) { hotel.reservation_imports.create!(user: user, status: "draft") }
  let(:boat_in_times) { %w[10:30 12:30 15:30] }
  let(:boat_out_times) { %w[09:30 11:30 14:30] }

  around { |example| travel_to(Time.zone.local(2026, 10, 1, 12)) { example.run } }

  before do
    ROOMS.each do |name, numbers|
      Rooms::SaveSeedRoomType.call!(
        hotel: hotel,
        attributes: { name: name, room_number_mode: "custom", quantity: numbers.size, base_price: 600.0,
                      max_adults: 4, max_children: 2, room_numbers: numbers }
      )
    end
    boat_in_times.each { |time| create(:hotel_boat_schedule, hotel: hotel, kind: "boat_in", time: time) }
    boat_out_times.each { |time| create(:hotel_boat_schedule, hotel: hotel, kind: "boat_out", time: time) }
    import.file.attach(io: File.open(fixture), filename: "sandbay.csv")
    Ezee::BuildImportRows.call(import: import)
  end

  def row(number) = import.rows.find_by!(reservation_number: number)

  describe "staging" do
    it "detects the layout and records it" do
      expect(import.reload.source_layout).to eq("reservation_csv")
    end

    it "skips past arrivals, as the Reservation List importer does" do
      expect(row("RES4433-1").status).to eq("past")
    end

    it "matches the file's category names to the property's, ignoring 'Room' and brackets" do
      matched = import.rows.where.not(room_type_id: nil).pluck(:room_type_name).uniq

      expect(matched).to include("Deluxe Room(King)", "Standard Room (Twin)")
      expect(import.rows.where(status: "blocked")).to be_empty
    end

    it "keeps released rows as cancelled history, with no room, even when they are in the past" do
      released = import.rows.where(booking_status: "cancelled")

      expect(released).to be_present
      expect(released.map(&:status).uniq).to eq(%w[importable])
      expect(released.map(&:room_id).compact).to be_empty
    end

    it "reads the agency from Business Source, not the guest name" do
      agent = import.rows.where.not(agency_name: nil).first

      expect(agent.agency_name).not_to eq(agent.guest_name)
    end

    it "warns about a resort-boat time the hotel does not run, and keeps the booking importable" do
      hotel.hotel_boat_schedules.where(kind: "boat_in", time: "15:30").destroy_all
      Ezee::BuildImportRows.call(import: import)

      cautioned = import.rows.with_issues.select { |r| r.issues.any? { |i| i["field"] == "boat" } }
      expect(cautioned).to be_present
      expect(cautioned.map(&:status)).not_to include("blocked")
    end
  end

  describe "rate plans" do
    let(:deluxe_king) { hotel.room_types.find_by!(name: "Deluxe King") }
    let(:plans) do
      { "Perfect Holiday" => 420, "International Agent Rate" => 650 }.to_h do |name, per_head|
        plan = create(:rate_plan, hotel: hotel, name: name, kind: "custom")
        assignment = create(:room_type_rate_plan, rate_plan: plan, room_type: deluxe_king, pricing_mode: "fixed")
        (1..4).each { |adults| assignment.occupancy_prices.create!(adults: adults, price: per_head * adults) }
        [ name, plan ]
      end
    end
    let(:deluxe_king_row) do
      Ezee::ReservationCsvParser.call(path: fixture).rows.find do |r|
        r.room_type == "Deluxe Room(King)" && r.arrival > Date.new(2026, 10, 1) && r.nights == 1 &&
          r.adults == 2 && r.children.zero? && r.rate_type == "Agent Rate International"
      end
    end

    def plan_for(row)
      Ezee::ImportPlan.call(hotel: hotel, rows: [ row ]).entries.first.rate_plan
    end

    it "matches the rate type on its words, whatever their order" do
      plans

      expect(plan_for(deluxe_king_row)).to eq(plans["International Agent Rate"])
    end

    it "puts an agency's booking on the plan named after it when that plan quotes the file's price" do
      plans
      deluxe_king_row.agency_name = "PERFECT VACATION SDN.BHD"
      deluxe_king_row.total_amount = 840

      expect(plan_for(deluxe_king_row)).to eq(plans["Perfect Holiday"])
    end

    it "does not, when the agency was charged something else: it stays on the plan the file names" do
      plans
      deluxe_king_row.agency_name = "PERFECT VACATION SDN.BHD"
      deluxe_king_row.total_amount = 1600

      expect(plan_for(deluxe_king_row)).to eq(plans["International Agent Rate"])
    end
  end

  describe "committing" do
    let!(:result) { Ezee::ImportReservations.call(import: import) }

    it "creates a booking for every importable row" do
      expect(result.failed.map { |r| [ r.reservation_number, r.issues.last ] }).to be_empty
      expect(result.created.size).to eq(import.rows.where(status: "created").count)
    end

    it "keeps the eZee reservation number and the file's stay total" do
      confirmed = import.rows.where(status: "created", booking_status: "confirmed").first
      booking = confirmed.booking

      expect(booking.external_reference).to eq(confirmed.reservation_number)
      expect(booking.total_amount).to eq(confirmed.total_amount)
      expect(booking.status).to eq("confirmed")
    end

    it "tags an agent's bookings as Travel Agent, the way the agent portal tags its own" do
      agent_rows = import.rows.where(status: "created").where.not(agency_name: nil)

      expect(agent_rows).to be_present
      expect(agent_rows.map { |row| row.booking.source }.uniq).to eq([ "travel_agent" ])
    end

    it "marks each agency local or international from the rate types it was booked on" do
      relationships = hotel.hotel_corporate_accounts.where.not(market: nil)

      expect(relationships).to be_present
      expect(relationships.pluck(:market).uniq - %w[local international]).to be_empty
    end

    it "leaves tourism tax off, because the export has no nationality" do
      expect(result.created.map(&:tourism_tax_amount).uniq).to eq([ 0 ])
    end

    it "records released rows as cancelled bookings that hold no room but keep the guest" do
      row = import.rows.where(status: "created", booking_status: "cancelled").first
      expect(row).to be_present
      booking = row.booking

      expect(booking.status).to eq("cancelled")
      expect(booking.primary_guest).to have_attributes(name: row.guest_name)
      expect(booking.booking_rooms.first.room_number).to be_blank
    end

    it "imports an unpaid hold as a confirmed booking marked as a hold, until pending can hold a room" do
      row = import.rows.where(status: "created", booking_status: "pending").first

      expect(row.booking.status).to eq("confirmed")
      expect(row.booking.internal_notes).to include("Unpaid hold in eZee")
    end

    it "keeps the remarks and who entered the booking in eZee" do
      row = import.rows.where(status: "created").where.not(remark: nil).where.not(booked_by: "").first

      expect(row.booking.special_requests).to eq(row.remark)
      expect(row.booking.internal_notes).to include("Entered in eZee by #{row.booked_by}")
    end

    it "writes the resort boat from the remark onto the booking guest" do
      row = import.rows.where(status: "created", boat_in_type: "provided", boat_out_type: "provided").first
      skip "no resort-boat row falls in the future" if row.nil?

      guest = row.booking.booking_guests.find(&:primary?)
      expect(guest.boat_in_type).to eq("provided")
      expect(Boats::Schedule.time_of_day(hotel: hotel, timestamp: guest.boat_in_at)).to eq(row.boat_in_time)
    end

    it "keeps an unpaid hold's assigned room, so it cannot be double-booked" do
      row = import.rows.where(status: "created", booking_status: "pending").where.not(room_id: nil).first
      expect(row).to be_present

      booking = row.booking
      available = Bookings::AvailableRoomNumbers.new(
        hotel: hotel, room_type: row.room_type, check_in: booking.check_in, check_out: booking.check_out
      ).call

      expect(booking.booking_rooms.first.room_number).to eq(row.room_number)
      expect(available).not_to include(row.room_number)
    end

    it "writes an own-boat transfer with no time" do
      row = import.rows.where(status: "created", boat_in_type: "own").first
      skip "no own-boat row falls in the future" if row.nil?

      expect(row.booking.booking_guests.find(&:primary?).boat_in_type).to eq("own")
    end
  end
end
