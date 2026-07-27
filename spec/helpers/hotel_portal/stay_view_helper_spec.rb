# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::StayViewHelper, type: :helper do
  around { |example| travel_to(Time.zone.local(2026, 7, 16, 10, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, accounting_business_date: Date.current) }
  let(:state) { StayView::BoardState.new(hotel:, params: { view: :rooms, date: Date.current }) }
  let(:capabilities) do
    StayView::Capabilities.new(
      **StayView::Capabilities.members.index_with { false }.merge(manage_bookings: true)
    )
  end

  before do
    current_hotel = hotel
    helper.define_singleton_method(:current_hotel) { current_hotel }
  end

  def segment(status, capabilities: self.capabilities)
    StayView::BookingSegment.new(
      dom_id: "stay-view-booking-1",
      booking_id: 123,
      booking_room_id: 456,
      guest_label: "Ada Lovelace",
      status:,
      check_in: Date.current,
      check_out: Date.current + 1.day,
      start_track: 1,
      end_track: 3,
      clipped_left: false,
      clipped_right: false,
      accessible_label: "Ada Lovelace, #{status}",
      capabilities:
    )
  end

  def lifecycle_actions(status, capabilities: self.capabilities)
    helper.stay_view_lifecycle_booking_actions(
      segment(status, capabilities:),
      { return_to: state.return_path(hotel), source: "stay_view" }
    ).map { |action| action.merge(data: action.fetch(:data, helper.stay_view_action_data)) }
  end

  it "derives the exact projected lifecycle action matrix from lifecycle events" do
    expected = {
      "pending" => [],
      "confirmed" => [ "Check-in", "Cancel" ],
      "review_no_show" => [ "Backdated Check-in", "Mark No-show", "Cancel" ],
      "checked_in" => [ "Check-out", "Edit Check-In", "Undo Check-in" ],
      "review_due_out" => [ "Review Late Checkout" ],
      "checkout_required" => [ "Complete Checkout" ],
      "cancelled" => [],
      "completed" => [],
      "overbooked" => [],
      "no_show" => [],
      "voided" => []
    }

    expect(expected.keys).to match_array(Booking::STATUSES)
    expected.each do |status, labels|
      expect(lifecycle_actions(status).pluck(:label)).to eq(labels), "unexpected actions for #{status}"
    end
  end

  it "builds every lifecycle action with its transaction route and Stay View state" do
    expected_paths = {
      "Check-in" => hotel_booking_action_check_in_path(hotel, 123),
      "Cancel" => hotel_booking_action_cancel_booking_path(hotel, 123),
      "Backdated Check-in" => hotel_booking_action_review_backdated_check_in_path(hotel, 123),
      "Mark No-show" => hotel_booking_action_mark_no_show_path(hotel, 123),
      "Check-out" => hotel_booking_action_checkout_path(hotel, 123),
      "Edit Check-In" => hotel_booking_action_check_in_path(hotel, 123),
      "Undo Check-in" => hotel_booking_action_undo_check_in_path(hotel, 123),
      "Review Late Checkout" => hotel_booking_action_late_checkout_path(hotel, 123),
      "Complete Checkout" => hotel_booking_action_checkout_path(hotel, 123)
    }
    actions = %w[confirmed review_no_show checked_in review_due_out checkout_required]
      .flat_map { |status| lifecycle_actions(status) }

    expect(actions.map { |action| action.fetch(:label) }).to include(*expected_paths.keys)
    actions.each do |action|
      uri = URI.parse(action.fetch(:href))
      query = Rack::Utils.parse_nested_query(uri.query)

      expect(uri.path).to eq(expected_paths.fetch(action.fetch(:label)))
      expect(query).to include("source" => "stay_view", "return_to" => state.return_path(hotel))
      sheet_actions = [ "Cancel", "Check-in", "Edit Check-In", "Mark No-show", "Undo Check-in", "Backdated Check-in", "Review Late Checkout", "Check-out", "Complete Checkout" ]
      expected_data = action.fetch(:label).in?(sheet_actions) ? helper.stay_view_booking_action_data : helper.stay_view_action_data
      expect(action.fetch(:data)).to eq(expected_data)
    end
  end

  it "does not expose lifecycle or internal events without manage bookings" do
    unauthorized = capabilities.with(manage_bookings: false, check_in: true, check_out: true)
    labels = Booking::STATUSES.flat_map { |status| lifecycle_actions(status, capabilities: unauthorized).pluck(:label) }

    expect(labels).to be_empty
    expect(labels).not_to include("Confirm", "Review no-show", "Mark overbooked", "Detect late checkout")
  end

  it "builds intent-scoped stay-editing actions for the Timeline booking drawer" do
    return_to = hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7)
    actions = helper.stay_view_drawer_booking_actions(
      123,
      capabilities: capabilities.with(move_booking: true, change_dates: false),
      return_to:
    )

    expect(actions.pluck(:label)).to eq([ "Change room", "Change rate" ])
    change_room = actions.find { |action| action[:label] == "Change room" }
    uri = URI.parse(change_room.fetch(:href))
    query = Rack::Utils.parse_nested_query(uri.query)
    expect(uri.path).to eq(hotel_booking_action_edit_room_path(hotel, 123))
    expect(query).to include("source" => "stay_view", "return_to" => return_to)
    expect(query).not_to have_key("proposal")
    expect(change_room.fetch(:data)).to eq(helper.stay_view_booking_action_data)
  end

  it "exposes Edit dates when only date changes are permitted" do
    actions = helper.stay_view_drawer_booking_actions(
      123,
      capabilities: capabilities.with(move_booking: false, change_dates: true),
      return_to: state.return_path(hotel)
    )

    expect(actions.pluck(:label)).to eq([ "Edit dates", "Change rate" ])
    edit_dates = actions.find { |action| action[:label] == "Edit dates" }
    expect(URI.parse(edit_dates.fetch(:href)).path).to eq(hotel_booking_action_edit_dates_path(hotel, 123))
  end

  it "reframes the board header copy per view mode" do
    expect(helper.stay_view_board_description(:timeline)).to include("across the coming days")
    expect(helper.stay_view_board_caption(:timeline)).to include("middle of check-in day")
    expect(helper.stay_view_board_description(:rooms)).to include("single day")
    expect(helper.stay_view_board_caption(:rooms)).to include("arrivals, departures, and turnovers")
  end

  it "falls back to the timeline header copy for an unknown view mode" do
    expect(helper.stay_view_board_description(:unknown)).to eq(helper.stay_view_board_description(:timeline))
    expect(helper.stay_view_board_caption(:unknown)).to eq(helper.stay_view_board_caption(:timeline))
  end
end
