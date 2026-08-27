# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ApplyFilters do
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false })
  end
  let(:hotel) { instance_double(Hotel, id: 9) }
  let(:reference_date) { Date.new(2026, 7, 16) }

  it "filters room attributes without rewriting booking occupancy" do
    confirmed = booking_segment(id: 1, status: :confirmed)
    checked_in = booking_segment(id: 2, status: :checked_in)
    matching_room = room_row(
      room_number: "101",
      physical_status: :dirty,
      occupancies: [
        StayView::Occupancy.new(state: :arrival, booking_id: 1, booking_status: :confirmed, label: "Arrival"),
        StayView::Occupancy.new(state: :occupied, booking_id: 2, booking_status: :checked_in, label: "Occupied")
      ],
      booking_segments: [ confirmed, checked_in ]
    )
    other_room = room_row(room_number: "102", physical_status: :ready)
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ matching_room, other_room ])
    filters = StayView::FilterState.build(
      room_type_id: 3,
      occupancy: :arrival,
      physical_status: :dirty
    )

    result = described_class.call(room_groups: [ group ], filters:)

    expect(result.one?).to be(true)
    expect(result.first.rooms.map(&:room_number)).to eq([ "101" ])
    expect(result.first.rooms.first.booking_segments).to eq([ confirmed, checked_in ])
    expect(result.first.rooms.first.day_cells.first.occupancies.map(&:booking_status)).to eq([ :confirmed, :checked_in ])
    expect(result).to be_frozen
  end

  it "filters Room View by the shared six-state resolver" do
    departure = booking_segment(id: 3, status: :completed).with(
      check_in: reference_date - 2.days,
      check_out: reference_date
    )
    arrival = booking_segment(id: 4, status: :confirmed)
    turnover = room_row(
      room_number: "101",
      physical_status: :ready,
      booking_segments: [ departure, arrival ]
    )
    vacant = room_row(room_number: "102", physical_status: :ready)
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ turnover, vacant ])
    filters = StayView::FilterState.build(room_state: :turnover).for_view(:rooms)

    result = described_class.call(
      room_groups: [ group ],
      filters:,
      hotel:,
      reference_date:,
      operational_date: reference_date
    )

    expect(result.first.rooms.map(&:room_number)).to eq([ "101" ])
  end

  private

  def booking_segment(id:, status:)
    StayView::BookingSegment.new(
      dom_id: "booking-#{id}",
      booking_id: id,
      booking_room_id: id,
      guest_label: "Guest #{id}",
      status:,
      check_in: reference_date,
      check_out: reference_date + 2.days,
      start_track: 2,
      end_track: 6,
      clipped_left: false,
      clipped_right: false,
      accessible_label: "Guest #{id}",
      capabilities:
    )
  end

  describe "room group filter" do
    let(:main_wing_room) { room_row(room_number: "101", physical_status: :ready, room_group_id: 7, room_group_name: "Main Wing") }
    let(:ungrouped_room) { room_row(room_number: "102", physical_status: :ready) }
    let(:group) { StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ main_wing_room, ungrouped_room ]) }

    def filtered(room_group_id)
      described_class.call(
        room_groups: [ group ],
        filters: StayView::FilterState.build(room_group_id:)
      ).flat_map(&:rooms).map(&:room_number)
    end

    it "keeps every room when no room group is selected" do
      expect(filtered(nil)).to eq(%w[101 102])
    end

    it "keeps the rooms of the selected room group" do
      expect(filtered(7)).to eq(%w[101])
    end

    it "keeps the ungrouped rooms on their own" do
      expect(filtered("__ungrouped__")).to eq(%w[102])
    end

    it "keeps no room when the selected group holds none" do
      expect(filtered(99)).to be_empty
    end
  end

  def room_row(room_number:, physical_status:, occupancies: [], booking_segments: [], room_group_id: nil,
               room_group_name: nil)
    StayView::RoomRow.new(
      key: "3:#{room_number}",
      dom_id: "room-#{room_number}",
      room_number:,
      room_type_id: 3,
      room_type_name: "Deluxe",
      room_group_id:,
      room_group_name:,
      smoking_allowed: false,
      pets_allowed: false,
      current_physical_status: physical_status,
      operational_flags: {},
      day_cells: [ StayView::DayCell.new(date: Date.new(2026, 7, 16), occupancies:) ],
      booking_segments:,
      operational_segments: [],
      capabilities:
    )
  end
end
