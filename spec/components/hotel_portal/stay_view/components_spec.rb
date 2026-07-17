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


  let(:housekeeping_alert) do
    ::StayView::HousekeepingAlert.new(
      request_id: 21,
      room_key: "1:101",
      details: "Replace towels and replenish the minibar before the guest returns",
      status: :assigned,
      requested_at: Time.zone.local(2026, 7, 16, 9, 30),
      assigned_to_id: 8,
      assigned_to_name: "Sam Lee",
      capabilities:
    )
  end

  let(:inventory_summary) do
    ::StayView::InventoryDateSummary.new(
      date: Date.new(2026, 7, 16),
      sellable: 4,
      sold: 1,
      available: 3,
      occupancy: 0.25
    )
  end

  it "renders a number-only inventory badge with its complete accessible meaning" do
    render_inline(HotelPortal::StayView::InventoryBadge.new(
      summary: inventory_summary,
      room_type_name: "Deluxe King"
    ))

    label = "3 available rooms for Deluxe King on #{I18n.l(inventory_summary.date, format: :long)}"
    expect(page).to have_css(
      ".panel-badge-rounded[data-slot='stay-view-inventory-badge'][data-variant='outline']" \
      "[role='img'][aria-label='#{label}']",
      text: "3"
    )
    expect(page.find("[data-slot='stay-view-inventory-badge']").text).to eq("3")
  end

  it "rejects inventory badge inputs outside the immutable projection contract" do
    expect do
      render_inline(HotelPortal::StayView::InventoryBadge.new(summary: Object.new, room_type_name: "Deluxe"))
    end.to raise_error(ArgumentError, /requires an inventory summary/)
  end

  it "renders a formatted standard rate beneath the inventory badge when authorized" do
    summary = inventory_summary.with(
      standard_rate: ::StayView::StandardRate.new(amount: 145, currency: "MYR", source: :room_rate)
    )
    render_inline(HotelPortal::StayView::RoomTypeDateSummary.new(
      summary:, room_type_name: "Deluxe King", view_rates: true
    ))

    expect(page.find("[data-slot='stay-view-inventory-badge']").text).to eq("3")
    expect(page).to have_css(
      "[data-slot='stay-view-standard-rate']" \
      "[aria-label='Standard nightly rate for Deluxe King on #{I18n.l(summary.date, format: :long)}: 145.00 MYR']",
      text: "145.00"
    )
    expect(page).to have_css(".panel-timeline__summary-metadata[data-slot='stay-view-standard-rate']")
  end

  it "renders N/A only for an authorized missing-rate state" do
    render_inline(HotelPortal::StayView::RoomTypeDateSummary.new(
      summary: inventory_summary, room_type_name: "Deluxe King", view_rates: true
    ))

    expect(page).to have_css("[data-slot='stay-view-standard-rate']", text: "N/A")
  end

  it "omits the complete rate node when unauthorized" do
    summary = inventory_summary.with(
      standard_rate: ::StayView::StandardRate.new(amount: 987.65, currency: "MYR", source: :room_rate)
    )
    render_inline(HotelPortal::StayView::RoomTypeDateSummary.new(
      summary:, room_type_name: "Deluxe King", view_rates: false
    ))

    expect(page).to have_css("[data-slot='stay-view-inventory-badge']", text: "3")
    expect(page).to have_no_css("[data-slot='stay-view-standard-rate']")
    expect(page.text).not_to include("987.65", "N/A", "MYR")
  end

  it "rejects room-type date summary inputs outside the immutable projection contract" do
    expect do
      render_inline(HotelPortal::StayView::RoomTypeDateSummary.new(
        summary: Object.new, room_type_name: "Deluxe", view_rates: true
      ))
    end.to raise_error(ArgumentError, /requires an inventory summary/)
  end

  it "renders a compact room summary from the immutable row projection" do
    render_inline(HotelPortal::StayView::RoomSummary.new(room: room, data: { room: "101" }))

    expect(page).to have_css("[data-slot='stay-view-room-summary'][data-room='101']", text: "101")
    expect(page).to have_no_css("[data-slot='stay-view-room-summary']", text: room.room_type_name)
    expect(page).to have_css("button[aria-label='Room status: Inspection failed'] .panel-badge-rounded[data-variant='destructive']")
    expect(page).to have_css("##{room.dom_id}-status-panel", text: "Inspection failed", visible: :all)
  end


  it "renders accessible current operational flags and housekeeping details" do
    operational_room = room.with(
      operational_flags: { dnd: true, priority: true },
      housekeeping_alerts: [ housekeeping_alert, housekeeping_alert.with(request_id: 22, assigned_to_name: nil) ]
    )

    render_inline(HotelPortal::StayView::OperationalIndicators.new(room: operational_room))

    expect(page).to have_css("[data-slot='stay-view-operational-indicators'][aria-label='Current operational indicators for room 101']")
    expect(page).to have_css("[role='img'][aria-label='Do not disturb'][tabindex='0']")
    expect(page).to have_css("[role='img'][aria-label='Priority room'][tabindex='0']")
    expect(page).to have_css("button[aria-label='2 active housekeeping requests']")
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel[role='dialog']", text: housekeeping_alert.details, visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel", text: "Assigned · Sam Lee", visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel", text: "Assigned · Unassigned", visible: :all)
    expect(page.native.to_html).not_to match(/(?:slate|gray|indigo|red|green)-\d+/)
  end

  it "renders no operational indicator wrapper when the room has no active flags or requests" do
    render_inline(HotelPortal::StayView::OperationalIndicators.new(room: room))

    expect(page).to have_no_css("[data-slot='stay-view-operational-indicators']")
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
      href: "/hotel/1/bookings/1"
    )
    expect(page.find("#stay-view-booking-1-trigger")[:"aria-label"]).to eq(booking_segment.accessible_label)
    expect(page.find("#stay-view-booking-1-trigger")).to have_text(booking_segment.guest_label)
    expect(page.find("#stay-view-booking-1-trigger")).to have_text("Checked in")
    expect(page).to have_css("#stay-view-booking-1[data-action*='mouseenter->panels-ui--popover#show']")
    expect(page).to have_css("#stay-view-booking-1-panel", text: "Single booking", visible: :all)
  end

  it "renders capability-gated pointer metadata and only visible resize handles" do
    interactive = booking_segment.with(
      clipped_left: true,
      clipped_right: false,
      capabilities: capabilities.with(move_booking: true, change_dates: true)
    )

    render_inline(HotelPortal::StayView::BookingBar.new(
      segment: interactive,
      interaction: {
        room_type_id: 1,
        room_number: "101",
        move_url: "/stay-view/bookings/1/move/edit?proposal=pointer",
        dates_url: "/stay-view/bookings/1/dates/edit?proposal=pointer"
      }
    ))

    expect(page).to have_css(
      "#stay-view-booking-1[data-stay-view--interaction-target='segment']" \
      "[data-action*='pointerdown->stay-view--interaction#start'][data-room-type-id='1'][data-room-number='101']"
    )
    expect(page).to have_css(".panel-timeline__resize-handle[data-resize-edge='end']", count: 1)
    expect(page).to have_no_css(".panel-timeline__resize-handle[data-resize-edge='start']")
    expect(page.find("#stay-view-booking-1-trigger")[:draggable]).to eq("false")
  end

  it "omits pointer hooks when booking mutations are not permitted" do
    render_inline(HotelPortal::StayView::BookingBar.new(segment: booking_segment))

    expect(page).to have_no_css("[data-stay-view--interaction-target='segment']")
    expect(page).to have_no_css(".panel-timeline__resize-handle")
  end

  it "shows group identity on a grouped booking segment" do
    grouped = booking_segment.with(
      group_booking_id: 7,
      group_reference: "0000001-1",
      group_name: "Tour Group",
      group_position: 2,
      booking_type: :group,
      group_rooms: [
        StayView::GroupRoomSummary.new(
          booking_id: 2,
          booking_room_id: 12,
          group_position: 1,
          room_number: "201",
          room_type_name: "Suite"
        )
      ]
    )

    render_inline(HotelPortal::StayView::BookingBar.new(segment: grouped))

    expect(page).to have_text("#{booking_segment.guest_label} · 0000001-1")
    expect(page).to have_css("#stay-view-booking-1-panel", text: "Group booking", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel", text: "201 – Suite", visible: :all)
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
    expect(page).to have_css("#stay-view-booking-1-trigger", text: "Reserved")
    expect(page).to have_css("#stay-view-booking-1-trigger", text: "Checked in")
    expect(page.find("#stay-view-booking-1-trigger")[:"aria-label"]).to eq(booking_segment.accessible_label)
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

  it "renders room identity with icon-only amenity tooltips" do
    restricted_room = room.with(pets_allowed: false)
    render_inline(HotelPortal::StayView::RoomSummary.new(
      room: restricted_room,
      actions: [ { href: "/rooms/101", icon: "sparkles", label: "Change status" } ]
    ))

    expect(page).to have_css("[data-slot='stay-view-room-summary']", text: "101")
    expect(page).to have_no_css("[data-slot='stay-view-room-summary']", text: room.room_type_name)
    expect(page).to have_css("[data-slot='stay-view-room-summary'] > .w-full.justify-between")
    expect(page).to have_css(".panel-badge-rounded[role='img'][aria-label='No smoking'][tabindex='0']")
    expect(page).to have_css(".panel-badge-rounded[role='img'][aria-label='No pets'][tabindex='0']")
    expect(page).to have_css("##{room.dom_id}-smoking-tooltip[role='tooltip']", text: "No smoking", visible: :all)
    expect(page).to have_css("##{room.dom_id}-pets-tooltip[role='tooltip']", text: "No pets", visible: :all)
    expect(page).to have_css(".panel-badge-rounded svg[aria-hidden='true']", count: 3)
    expect(page).to have_css("##{room.dom_id}-actions-trigger svg", count: 1)
  end

  it "renders recursive booking actions separately from root room actions" do
    render_inline(HotelPortal::StayView::RoomSummary.new(
      room: room,
      actions: [
        {
          label: "Booking",
          id: "room-101-bookings",
          children: [
            {
              label: "Jack",
              id: "room-101-booking-1",
              children: [
                {
                  href: "/bookings/1/move",
                  icon: "move",
                  label: "Move or reassign",
                  data: { turbo_frame: "offcanvas_drawer" }
                }
              ]
            }
          ]
        },
        { href: "/rooms/101/status", icon: "sparkles", label: "Change room status" }
      ]
    ))

    expect(page).to have_css("#room-101-bookings[aria-label='Booking'] #room-101-booking-1[aria-label='Jack']", visible: :all)
    expect(page).to have_css("#room-101-booking-1 a[data-turbo-frame='offcanvas_drawer']", text: "Move or reassign", visible: :all)
    expect(page).to have_css("##{room.dom_id}-actions-menu > a", text: "Change room status", visible: :all)
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
