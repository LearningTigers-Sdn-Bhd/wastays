# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::BoardBuilder, frozen_time: Time.zone.local(2026, 8, 15, 12) do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, accounting_business_date: selected_date) }
  let(:selected_date) { Date.new(2026, 8, 15) }
  let!(:penthouse) do
    create(:room_type, hotel:, name: "Executive Penthouse", room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102])
  end
  let!(:garden_suite) do
    create(:room_type, hotel:, name: "Garden Suite", room_number_mode: "custom", quantity: 1, room_numbers: %w[101])
  end

  def build_board(**filters)
    described_class.new(hotel:, date: selected_date, **filters).call
  end

  def room(room_type_name, number = "101", **filters)
    build_board(**filters).find do |entry|
      entry[:room_type].name == room_type_name && entry[:room_number] == number
    end
  end

  def stay(room_type: penthouse, room_number: "101", status:, check_in:, check_out:, **attributes)
    booking = create(:booking, hotel:, status:, check_in:, check_out:, **attributes)
    create(:booking_room, booking:, room_type:, room_number:)
    booking
  end

  it "returns exactly one row per physical room without task placeholders" do
    rows = build_board

    expect(rows.map { |entry| [ entry[:room_type].name, entry[:room_number] ] }).to contain_exactly(
      [ "Executive Penthouse", "101" ],
      [ "Executive Penthouse", "102" ],
      [ "Garden Suite", "101" ]
    )
    expect(rows).to all(satisfy { |entry| !entry.key?(:hk_requests) })
  end

  it "keeps rooms with the same number isolated by room type" do
    stay(
      status: "checked_in",
      check_in: selected_date - 1.day,
      check_out: selected_date + 1.day,
      guest_name: "Penthouse Guest"
    )

    expect(room("Executive Penthouse")[:booking_status]).to eq("in_house")
    expect(room("Garden Suite")[:booking_status]).to eq("vacant")
  end

  describe "booking status projection" do
    it "projects the agreed precedence and labels" do
      stay(
        status: "checked_in",
        check_in: selected_date - 1.day,
        check_out: selected_date,
        adults: 3,
        children: 1
      )

      projected = room("Executive Penthouse")
      expect(projected).to include(
        booking_status: "pending_checkout",
        booking_status_label: "Pending checkout",
        pax: "3/1"
      )
    end

    {
      "checked_out" => { status: "completed", check_in: -2, check_out: 0, checked_out_at: 11.hours },
      "checkout_required" => { status: "checkout_required", check_in: -1, check_out: 0 },
      "pending_checkout" => { status: "due_out_detected", check_in: -1, check_out: 0 },
      "day_use" => { status: "checked_in", check_in: 0, check_out: 0 },
      "checked_in_today" => { status: "checked_in", check_in: 0, check_out: 2, checked_in_at: 10.hours },
      "in_house" => { status: "checked_in", check_in: -2, check_out: 2 },
      "day_use_reservation" => { status: "confirmed", check_in: 0, check_out: 0 },
      "arriving_today" => { status: "confirmed", check_in: 0, check_out: 2 }
    }.each do |expected, details|
      it "maps a booking to #{expected.humanize}" do
        checked_in_at = details[:checked_in_at] && selected_date.in_time_zone(hotel.hotel_time_zone) + details[:checked_in_at]
        checked_out_at = details[:checked_out_at] && selected_date.in_time_zone(hotel.hotel_time_zone) + details[:checked_out_at]
        stay(
          status: details.fetch(:status),
          check_in: selected_date + details.fetch(:check_in).days,
          check_out: selected_date + details.fetch(:check_out).days,
          checked_in_at:,
          checked_out_at:
        )

        expect(room("Executive Penthouse")[:booking_status]).to eq(expected)
      end
    end

    it "gives an active block precedence over a booking" do
      stay(status: "checked_in", check_in: selected_date - 1.day, check_out: selected_date + 1.day)
      create(
        :room_block,
        hotel:,
        room_type: penthouse,
        room_number: "101",
        start_date: selected_date,
        end_date: selected_date,
        user: create(:user, account:)
      )

      expect(room("Executive Penthouse")).to include(
        booking_status: "out_of_order",
        resolved_status: "out_of_service"
      )
    end

    it "shows a room without an applicable booking as vacant with no pax" do
      expect(room("Garden Suite")).to include(booking_status: "vacant", pax: "—")
    end

    it "exposes late checkout eligibility only after the exact checked-in stay cutoff" do
      stay(
        status: "checked_in",
        check_in: selected_date - 1.day,
        check_out: selected_date.in_time_zone(hotel.hotel_time_zone) + 11.hours
      )

      expect(room("Executive Penthouse")[:late_checkout_eligible]).to be(true)
      expect(room("Garden Suite")[:late_checkout_eligible]).to be(false)
    end
  end

  describe "filters and sorting" do
    let(:housekeeper) { create(:user, account:, name: "Ari Housekeeper") }

    before do
      create(
        :room_status,
        hotel:,
        room_type: penthouse,
        room_number: "101",
        status: "dirty",
        assigned_to: housekeeper,
        notes: "Bring hypoallergenic pillows"
      )
      create(:room_status, hotel:, room_type: penthouse, room_number: "102", status: "ready")
      stay(
        status: "checked_in",
        check_in: selected_date - 1.day,
        check_out: selected_date,
        guest_name: "Ada Lovelace",
        confirmation_token: "WS-ADA1"
      )
      stay(
        room_number: "102",
        status: "checked_in",
        check_in: selected_date - 2.days,
        check_out: selected_date + 2.days
      )
    end

    it "filters by room type and physical room status" do
      results = build_board(
        room_type_ids: [ penthouse.id ],
        room_statuses: [ "dirty" ],
        assigned_to_ids: [ housekeeper.id ],
        booking_statuses: [ "pending_checkout" ]
      )

      expect(results.one?).to be(true)
      expect(results.first[:room_number]).to eq("101")
    end

    it "sorts the flat room list by arrival or departure" do
      results = build_board(sort: "departure", direction: "desc")

      expect(results.first[:room_type]).to eq(penthouse)
      expect(results.first(2).map { |entry| entry[:room_number] }).to eq([ "102", "101" ])
    end

    it "uses natural room-number order across room types by default" do
      penthouse.update!(quantity: 4, room_numbers: %w[101 102 10 2])

      expect(build_board.map { |entry| entry[:room_number] }).to eq(%w[2 10 101 101 102])
    end
  end

  describe "room groups" do
    let!(:main_wing) { create(:room_group, hotel:, name: "Main Wing") }
    let!(:annexe) { create(:room_group, hotel:, name: "Annexe") }

    before do
      penthouse.update!(quantity: 2, room_numbers: %w[101 102])
      garden_suite.update!(quantity: 1, room_numbers: %w[201])
      create(:room, hotel:, room_type: penthouse, number: "101", room_group: main_wing)
      create(:room, hotel:, room_type: penthouse, number: "102")
      create(:room, hotel:, room_type: garden_suite, number: "201", room_group: annexe)
    end

    it "names the room group of each room and calls the rest ungrouped" do
      rows = build_board.index_by { |entry| entry[:room_number] }

      expect(rows["101"][:room_group_name]).to eq("Main Wing")
      expect(rows["101"][:room_group_id]).to eq(main_wing.id)
      expect(rows["102"][:room_group_name]).to eq("Ungrouped")
      expect(rows["102"][:room_group_id]).to be_nil
    end

    it "filters by room group" do
      rows = build_board(room_group_ids: [ annexe.id ])

      expect(rows.map { |entry| entry[:room_number] }).to eq(%w[201])
    end

    it "filters the ungrouped rooms on their own" do
      rows = build_board(room_group_ids: [ "__ungrouped__" ])

      expect(rows.map { |entry| entry[:room_number] }).to eq(%w[102])
    end

    it "keeps every room when no room group is selected" do
      expect(build_board(room_group_ids: []).size).to eq(3)
    end

    it "orders the board by room group and puts ungrouped rooms last" do
      rows = build_board(group_by: "room_group")

      expect(rows.map { |entry| entry[:room_group_name] }).to eq([ "Annexe", "Main Wing", "Ungrouped" ])
      expect(rows.map { |entry| entry[:room_number] }).to eq(%w[201 101 102])
    end

    it "orders the board by room type name" do
      rows = build_board(group_by: "room_type")

      expect(rows.map { |entry| entry[:room_type].name }).to eq(
        [ "Executive Penthouse", "Executive Penthouse", "Garden Suite" ]
      )
    end

    it "keeps natural room-number order when the grouping is flat" do
      expect(build_board(group_by: "none").map { |entry| entry[:room_number] }).to eq(%w[101 102 201])
    end

    it "sorts inside a section, not across sections" do
      stay(room_type: garden_suite, room_number: "201", status: "checked_in",
           check_in: selected_date - 3.days, check_out: selected_date + 1.day)

      rows = build_board(group_by: "room_group", sort: "arrival", direction: "asc")

      expect(rows.map { |entry| entry[:room_group_name] }).to eq([ "Annexe", "Main Wing", "Ungrouped" ])
    end
  end
end
