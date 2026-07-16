# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::StayView components", type: :component do
  let(:capabilities) do
    ::StayView::Capabilities.new(
      **::StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_booking: true)
    )
  end

  let(:booking_segment) do
    ::StayView::BookingSegment.new(
      dom_id: "stay-view-booking-1",
      booking_id: 1,
      booking_room_id: 11,
      guest_label: "Ada Lovelace with a guest name that is deliberately long",
      status: :checked_in,
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 18),
      start_track: 2,
      end_track: 6,
      clipped_left: true,
      clipped_right: false,
      accessible_label: "Ada Lovelace, checked in, room 101, Deluxe King, 16 July 2026 to 18 July 2026",
      capabilities: capabilities
    )
  end

  let(:operational_segment) do
    ::StayView::OperationalSegment.new(
      dom_id: "stay-view-block-1",
      kind: :maintenance,
      label: "Air-conditioning maintenance",
      start_date: Date.new(2026, 7, 17),
      end_date: Date.new(2026, 7, 19),
      start_track: 3,
      end_track: 7,
      clipped_left: false,
      clipped_right: true,
      accessible_label: "Air-conditioning maintenance, room 101, 17 July 2026 to 18 July 2026",
      capabilities: capabilities
    )
  end

  let(:room) do
    ::StayView::RoomRow.new(
      key: "1:101",
      dom_id: "stay-view-room-101",
      room_number: "101",
      room_type_id: 1,
      room_type_name: "Deluxe King with a room type name that is deliberately long",
      smoking_allowed: false,
      pets_allowed: true,
      current_physical_status: :inspection_failed,
      operational_flags: {},
      day_cells: [],
      booking_segments: [ booking_segment ],
      operational_segments: [ operational_segment ],
      capabilities: capabilities
    )
  end

  it "renders a compact room summary from the immutable row projection" do
    render_inline(HotelPortal::StayView::RoomSummary.new(room: room, data: { room: "101" }))

    expect(page).to have_css("[data-slot='stay-view-room-summary'][data-room='101']", text: "101")
    expect(page).to have_css(".truncate", text: room.room_type_name)
    expect(page).to have_css(".panel-badge[data-variant='destructive']", text: "Inspection failed")
  end

  it "maps an editable booking projection to an actionable semantic segment" do
    render_inline(HotelPortal::StayView::BookingBar.new(
      segment: booking_segment,
      href: "/hotel/1/bookings/1",
      link_attributes: { data: { turbo_frame: "stay-view" } }
    ))

    expect(page).to have_css(
      "#stay-view-booking-1.panel-timeline__segment[data-tone='success'][data-emphasis='solid']" \
      "[data-clipped-left='true'][data-clipped-right='false']"
    )
    expect(page).to have_link(
      booking_segment.guest_label,
      href: "/hotel/1/bookings/1",
      exact: true
    )
    expect(page.find("#stay-view-booking-1 a")[:"aria-label"]).to eq(booking_segment.accessible_label)
  end

  it "shows group identity on a grouped booking segment" do
    grouped = booking_segment.with(group_booking_id: 7, group_reference: "0000001-1", group_name: "Tour Group", group_position: 2)

    render_inline(HotelPortal::StayView::BookingBar.new(segment: grouped))

    expect(page).to have_text("#{booking_segment.guest_label} · 0000001-1")
  end

  it "allows a composition to namespace booking and operational segment ids" do
    render_inline(HotelPortal::StayView::BookingBar.new(segment: booking_segment, id: "light-booking-1"))
    expect(page).to have_css("#light-booking-1.panel-timeline__segment")
    expect(page).to have_no_css("#stay-view-booking-1")

    render_inline(HotelPortal::StayView::OperationalBar.new(segment: operational_segment, id: "light-block-1"))
    expect(page).to have_css("#light-block-1.panel-timeline__segment")
    expect(page).to have_no_css("#stay-view-block-1")
  end

  it "omits a booking link when the projection does not permit booking details" do
    redacted = booking_segment.with(capabilities: capabilities.with(view_booking: false), guest_label: "Reserved")

    render_inline(HotelPortal::StayView::BookingBar.new(segment: redacted, href: "/hotel/1/bookings/1"))

    expect(page).to have_no_link
    expect(page).to have_css("[role='img'][aria-label='#{booking_segment.accessible_label}']", text: "Reserved")
  end

  it "maps operational projections to a hatched lower lane" do
    render_inline(HotelPortal::StayView::OperationalBar.new(segment: operational_segment))

    expect(page).to have_css(
      "#stay-view-block-1.panel-timeline__segment[data-tone='warning'][data-emphasis='hatched']" \
      "[data-clipped-right='true']",
      text: "Air-conditioning maintenance"
    )
    expect(page).to have_no_link
  end

  it "rejects objects outside the Phase 1 projection contract" do
    expect { render_inline(HotelPortal::StayView::RoomSummary.new(room: Object.new)) }
      .to raise_error(ArgumentError, /StayView::RoomRow/)
    expect { render_inline(HotelPortal::StayView::BookingBar.new(segment: Object.new)) }
      .to raise_error(ArgumentError, /StayView::BookingSegment/)
    expect { render_inline(HotelPortal::StayView::OperationalBar.new(segment: Object.new)) }
      .to raise_error(ArgumentError, /StayView::OperationalSegment/)
  end
end
