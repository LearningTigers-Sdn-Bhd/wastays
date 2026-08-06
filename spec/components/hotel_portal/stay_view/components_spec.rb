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
      status_note: "Dust remains on the headboard after inspection",
      priority_note: "Prepare before the early arrival",
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
      assignment_history: [
        ::StayView::HousekeepingAssignmentEvent.new(
          assigned_to_name: "Sam Lee",
          assigned_by_name: "Alex Manager",
          timestamp: Time.zone.local(2026, 7, 16, 8, 30)
        )
      ],
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

  let(:footer_summary) do
    ::StayView::FooterDateSummary.new(
      date: Date.new(2026, 7, 16),
      sellable: 3,
      sold: 2,
      available: 1,
      occupancy: 2.0 / 3
    )
  end

  let(:status_counts) do
    ::StayView::StatusCounts.new(
      reference_date: Date.new(2026, 7, 16),
      room_states: {
        all: 6, vacant: 0, arrival: 1, occupied: 2, departure: 1, turnover: 1, blocked: 1, dirty: 1
      }
    )
  end

  it "renders every operational count badge, including zero values, in a fixed order" do
    render_inline(HotelPortal::StayView::OperationalCounts.new(counts: status_counts))

    badges = page.all("[data-slot='stay-view-operational-count']")
    expect(badges.map { |badge| badge["data-state"] }).to eq(
      %w[all vacant arrival occupied departure turnover blocked dirty]
    )
    expect(badges.map { |badge| badge.all("span").map(&:text) }).to eq(
      [ [ "All", "6" ], [ "Vacant", "0" ], [ "Arrival", "1" ], [ "Occupied", "2" ],
       [ "Departure", "1" ], [ "Turnover", "1" ], [ "Blocked", "1" ], [ "Dirty", "1" ] ]
    )
    expect(page).to have_css("[data-state='vacant'][data-variant='outline'][aria-label='Vacant: 0 rooms']")
    expect(badges.map { |badge| badge["data-variant"] }.uniq).to eq([ "outline" ])
  end

  it "hides the turnover count in the timeline view" do
    render_inline(HotelPortal::StayView::OperationalCounts.new(counts: status_counts, view_mode: :timeline))

    expect(page.all("[data-slot='stay-view-operational-count']").map { |badge| badge["data-state"] }).to eq(
      %w[all vacant arrival occupied departure blocked dirty]
    )
  end

  it "renders only Stay View statuses and permission-gates financial guide entries" do
    render_inline(HotelPortal::StayView::StatusGuide.new(view_booking: false, view_financial_status: false))

    expect(page).to have_css("button[aria-label='Stay View status guide']")
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Arrival", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "In-house", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Completed", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Do not disturb", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Cleaning priority", visible: :all)
    expect(page).to have_no_css("#stay-view-status-guide-panel", text: "Timeline events", visible: :all)
    expect(page).to have_no_css("#stay-view-status-guide-panel", text: "Departure", visible: :all)
    expect(page).to have_no_css("#stay-view-status-guide-panel", text: "No-show detected", visible: :all)
    expect(page).to have_css("div[data-slot='stay-view-status-swatch']", count: 17)
    expect(page).to have_css("div[data-slot='stay-view-status-swatch'] svg.size-3", count: 17)
    expect(page).to have_no_css("#stay-view-status-guide-panel .panel-badge-rounded", visible: :all)
    expect(page).to have_css(
      "[data-slot='stay-view-status-swatch'][data-state='arrival']" \
      "[data-presentation='segment'][data-tone='info'][data-emphasis='solid'] svg"
    )
    expect(page).to have_css(
      "[data-slot='stay-view-status-swatch'][data-state='in_house']" \
      "[data-presentation='segment'][data-tone='success'][data-emphasis='solid'] svg"
    )
    expect(page).to have_css(
      "[data-slot='stay-view-status-swatch'][data-state='completed']" \
      "[data-presentation='segment'][data-tone='completed'][data-emphasis='solid'] svg"
    )
    expect(page).to have_css(
      ".panel-badge.panel-timeline__legend-swatch[data-state='dirty']" \
      "[data-presentation='badge'][data-variant='warning'] svg"
    )
    expect(page).to have_css(
      "[data-slot='stay-view-status-swatch'][data-state='maintenance']" \
      "[data-presentation='segment'][data-tone='warning'][data-emphasis='hatched'] svg"
    )
    expect(page).to have_no_css("#stay-view-status-guide-panel", text: "Payment needed", visible: :all)
    expect(page).to have_no_css("#stay-view-status-guide-panel", text: "Guest status", visible: :all)
    expect(page).to have_no_text("Single Lady")

    render_inline(HotelPortal::StayView::StatusGuide.new(view_booking: true, view_financial_status: true))

    expect(page).to have_css("#stay-view-status-guide-panel", text: "Payment needed", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Company pays", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Guest status", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Blacklisted", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "VIP", visible: :all)
    expect(page).to have_css("#stay-view-status-guide-panel", text: "Repeat", visible: :all)
    expect(page).to have_css(
      ".panel-badge.panel-timeline__legend-swatch[data-state='financial_attention']" \
      "[data-presentation='badge'][data-variant='warning'] svg"
    )
  end

  it "renders a number-only footer value and rounded occupancy with complete accessible labels" do
    render_inline(HotelPortal::StayView::TimelineFooterMetric.new(summary: footer_summary, metric: :available))

    formatted_date = I18n.l(footer_summary.date, format: :long)
    expect(page).to have_css(
      "[data-slot='stay-view-footer-available'].font-semibold.tabular-nums" \
      "[aria-label='1 available room on #{formatted_date}']",
      text: "1"
    )
    expect(page).to have_no_css("[data-slot='stay-view-footer-occupancy']")

    render_inline(HotelPortal::StayView::TimelineFooterMetric.new(summary: footer_summary, metric: :occupancy))

    expect(page).to have_css(
      "[data-slot='stay-view-footer-occupancy'][aria-label='67 percent occupied on #{formatted_date}']",
      text: "67%"
    )
    expect(page).to have_no_css("[data-slot='stay-view-footer-available']")
  end

  it "renders an accessible unavailable occupancy state for zero sellable inventory" do
    summary = footer_summary.with(sellable: 0, sold: 0, available: 0, occupancy: nil)

    render_inline(HotelPortal::StayView::TimelineFooterMetric.new(summary:, metric: :occupancy))

    expect(page).to have_css(
      "[data-slot='stay-view-footer-occupancy'][aria-label*='because sellable inventory is zero']",
      text: "N/A"
    )
  end

  it "rejects footer metric inputs outside the immutable projection contract" do
    expect do
      render_inline(HotelPortal::StayView::TimelineFooterMetric.new(summary: Object.new, metric: :available))
    end.to raise_error(ArgumentError, /requires a footer summary/)

    expect do
      render_inline(HotelPortal::StayView::TimelineFooterMetric.new(summary: footer_summary, metric: :revenue))
    end.to raise_error(ArgumentError, /metric must be one of/)
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

  it "reuses the nightly rate in a currency-labelled room-card presentation" do
    summary = inventory_summary.with(
      standard_rate: ::StayView::StandardRate.new(amount: 145, currency: "MYR", source: :room_rate)
    )
    render_inline(HotelPortal::StayView::NightlyRate.new(
      summary:, room_type_name: "Deluxe King", view_rates: true, context: :room_card
    ))

    rate = page.find("[data-slot='stay-view-standard-rate'][data-context='room_card']")
    expect(rate.text.squish).to eq("MYR 145.00")
    expect(rate["aria-label"]).to eq(
      "Standard nightly rate for Deluxe King on #{I18n.l(summary.date, format: :long)}: 145.00 MYR"
    )
    expect(rate).to have_css("svg[aria-hidden='true']")
  end

  it "renders the shared N/A state in a room card" do
    render_inline(HotelPortal::StayView::NightlyRate.new(
      summary: inventory_summary, room_type_name: "Deluxe King", view_rates: true, context: :room_card
    ))
    expect(page).to have_css("[data-slot='stay-view-standard-rate'][data-context='room_card']", text: "N/A")
  end

  it "completely redacts an unauthorized room-card rate" do
    render_inline(HotelPortal::StayView::NightlyRate.new(
      summary: inventory_summary.with(
        standard_rate: ::StayView::StandardRate.new(amount: 987.65, currency: "MYR", source: :room_rate)
      ),
      room_type_name: "Deluxe King",
      view_rates: false,
      context: :room_card
    ))

    expect(page).to have_no_css("[data-slot='stay-view-standard-rate']")
    expect(page.text).not_to include("987.65", "N/A", "MYR")
  end

  it "rejects invalid nightly-rate presentation inputs" do
    expect do
      render_inline(HotelPortal::StayView::NightlyRate.new(
        summary: Object.new, room_type_name: "Deluxe", view_rates: true, context: :card
      ))
    end.to raise_error(ArgumentError, /requires an inventory summary/)
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
    expect(page).to have_css("button[aria-label='Room status: Inspection failed'] .panel-badge-circular[data-variant='destructive']")
    expect(page).to have_css("##{room.dom_id}-status[data-action*='mouseenter->panels-ui--popover#show']")
    expect(page).to have_css("##{room.dom_id}-status[data-action*='focusin->panels-ui--popover#show']")
    expect(page).to have_css("##{room.dom_id}-status-panel", text: "Inspection failed", visible: :all)
    expect(page).to have_css("##{room.dom_id}-status-panel", text: "Dust remains on the headboard", visible: :all)
  end


  it "renders accessible current operational flags and housekeeping details" do
    operational_room = room.with(
      capabilities: capabilities.with(view_room_readiness: true),
      operational_flags: { dnd: true, priority: true },
      housekeeping_alerts: [ housekeeping_alert, housekeeping_alert.with(request_id: 22, assigned_to_name: nil) ]
    )

    render_inline(HotelPortal::StayView::OperationalIndicators.new(room: operational_room))

    expect(page).to have_css("[data-slot='stay-view-operational-indicators'][aria-label='Current operational indicators for room 101']")
    expect(page).to have_css("button[aria-label='Do not disturb: on'] [data-slot='stay-view-dnd-indicator'][data-state='on']")
    expect(page).to have_css("button[aria-label='Cleaning priority: on'] [data-slot='stay-view-priority-indicator'][data-state='on']")
    expect(page).to have_css("##{room.dom_id}-priority-panel", text: "Prepare before the early arrival", visible: :all)
    expect(page).to have_css("button[aria-label='2 active housekeeping requests']")
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel[role='dialog']", text: housekeeping_alert.details, visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel [role='alert']", text: "Do not enter / do not clean", visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel", text: "Assigned · Sam Lee", visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-panel", text: "Assigned · Unassigned", visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-21-history[data-state='closed']", visible: :all)
    expect(page).to have_css("##{room.dom_id}-housekeeping-21-history-content", text: "Assigned to Sam Lee", visible: :all)
    expect(page.native.to_html).not_to match(/(?:slate|gray|indigo|red|green)-\d+/)
  end

  it "splits room-card restrictions from controls in the required order" do
    operational_room = room.with(
      smoking_allowed: false,
      pets_allowed: false,
      capabilities: capabilities.with(view_room_readiness: true),
      housekeeping_alerts: [ housekeeping_alert ]
    )

    render_inline(HotelPortal::StayView::RoomSummary.new(
      room: operational_room,
      layout: :split_controls,
      show_identity: false
    ))

    summary = page.find("[data-slot='stay-view-room-summary']")
    html = summary.native.to_html
    expect(html.index("aria-label=\"No pets\"")).to be < html.index("aria-label=\"No smoking\"")
    expect(html.index("#{room.dom_id}-status")).to be < html.index("#{room.dom_id}-dnd")
    expect(html.index("#{room.dom_id}-dnd")).to be < html.index("#{room.dom_id}-priority")
    expect(html.index("#{room.dom_id}-priority")).to be < html.index("#{room.dom_id}-housekeeping")
  end

  it "renders both readiness flags in their off state for authorized viewers" do
    authorized_room = room.with(capabilities: capabilities.with(view_room_readiness: true))

    render_inline(HotelPortal::StayView::OperationalIndicators.new(room: authorized_room))

    expect(page).to have_css("button[aria-label='Do not disturb: off'] [data-slot='stay-view-dnd-indicator'][data-state='off'][data-variant='outline']")
    expect(page).to have_css("button[aria-label='Cleaning priority: off'] [data-slot='stay-view-priority-indicator'][data-state='off'][data-variant='outline']")
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
    expect(page).to have_css("#stay-view-booking-1-trigger .stay-view-booking-guest-name", text: booking_segment.guest_label)
    expect(page.find("#stay-view-booking-1-trigger")).to have_no_text("Checked in")
    expect(page).to have_css("#stay-view-booking-1[data-action*='mouseenter->panels-ui--popover#show']")
    expect(page).to have_css("#stay-view-booking-1-panel", text: "Single booking", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel dt", text: "Status", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel dd", text: "Checked in", visible: :all)
  end

  it "groups booking lifecycle statuses into distinct timeline stage tones" do
    {
      confirmed: "info",
      no_show_detected: "warning",
      checked_in: "success",
      due_out_detected: "warning",
      checkout_required: "destructive",
      completed: "completed"
    }.each do |status, tone|
      render_inline(HotelPortal::StayView::BookingBar.new(segment: booking_segment.with(status:)))

      expect(page).to have_css("#stay-view-booking-1[data-tone='#{tone}']")
    end
  end

  it "shows the booking source at the left of the bar and in the popover when present" do
    render_inline(HotelPortal::StayView::BookingBar.new(segment: booking_segment.with(source: "walk_in", source_label: "Walk-in")))

    trigger = page.find("#stay-view-booking-1-trigger")
    source = trigger.find("[data-slot='stay-view-booking-source']")
    expect(source).to have_css("[aria-hidden='true']")
    expect(source).to have_no_css("[tabindex]")
    expect(trigger.all("[data-slot='stay-view-booking-source'], .stay-view-booking-guest-name").map { |node| node[:class] }.first)
      .to include("shrink-0")
    heading = page.find("#stay-view-booking-1-panel", visible: :all)
    expect(heading).to have_css("[data-slot='stay-view-popover-source']", visible: :all)
    expect(heading).to have_text("via Walk-in")
    expect(page).to have_no_css("#stay-view-booking-1-panel dt", text: "Source", visible: :all)
  end

  it "shows guest status icons beside the guest name inside the popover" do
    segment = booking_segment.with(
      vip: true,
      blacklisted: true,
      repeat: true,
      accessible_label: "#{booking_segment.accessible_label}, guest status Blacklisted, VIP, and Repeat"
    )

    render_inline(HotelPortal::StayView::BookingBar.new(segment:))

    expect(page).to have_no_css("#stay-view-booking-1-trigger [data-slot='stay-view-guest-status']")
    expect(page).to have_css("#stay-view-booking-1-panel [data-slot='stay-view-guest-status'][data-status='blacklisted'][aria-label='Blacklisted guest']", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel [data-slot='stay-view-guest-status'][data-status='vip'][aria-label='VIP guest']", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel [data-slot='stay-view-guest-status'][data-status='repeat'][aria-label='Repeat guest']", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel [data-slot='stay-view-guest-status'] svg[aria-hidden='true']", count: 3, visible: :all)
    expect(page).to have_no_css("#stay-view-booking-1-panel dt", text: "Guest status", visible: :all)
    expect(page.find("#stay-view-booking-1-trigger")[:"aria-label"]).to include("guest status Blacklisted, VIP, and Repeat")
  end

  it "renders a colored OTA badge for a recognized channel source" do
    render_inline(HotelPortal::StayView::BookingBar.new(segment: booking_segment.with(source: "booking.com", source_label: "Booking.com")))

    panel = page.find("#stay-view-booking-1-panel", visible: :all)
    expect(panel).to have_text("via Booking.com")
    expect(panel).to have_css("[data-slot='stay-view-popover-source'] span", text: "B", visible: :all)
  end

  it "keeps financial attention off the bar and shows full details in the popover" do
    credit = StayView::FinancialSignal.new(
      state: :credit,
      label: "Guest: Ada Lovelace · Credit · MYR 20.00"
    )
    balance = StayView::FinancialSignal.new(
      state: :balance_due,
      label: "Unpaid MYR 240.00 · Acme"
    )
    segment = booking_segment.with(
      financial_signals: [ credit, balance ],
      accessible_label: "#{booking_segment.accessible_label}, #{credit.label}, #{balance.label}"
    )

    render_inline(HotelPortal::StayView::BookingBar.new(segment:))

    expect(page).to have_no_css("#stay-view-booking-1-trigger [data-slot='stay-view-financial-attention']")
    expect(page).to have_css("#stay-view-booking-1-panel", text: credit.label, visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel", text: balance.label, visible: :all)
    expect(page.find("#stay-view-booking-1-trigger")[:"aria-label"]).to include(credit.label, balance.label)
  end

  it "shows settled and Direct Bill details only in the popover" do
    settled = StayView::FinancialSignal.new(state: :settled, label: "Nothing due")
    direct_bill = StayView::FinancialSignal.new(
      state: :direct_bill_planned,
      label: "Company pays MYR 240.00 · Acme"
    )

    render_inline(
      HotelPortal::StayView::BookingBar.new(segment: booking_segment.with(financial_signals: [ settled, direct_bill ]))
    )

    expect(page).to have_no_css("[data-slot='stay-view-financial-attention']")
    expect(page).to have_css("#stay-view-booking-1-panel", text: "Nothing due", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel", text: direct_bill.label, visible: :all)
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

    expect(page.find("#stay-view-booking-1-trigger")).to have_text(booking_segment.guest_label)
    expect(page.find("#stay-view-booking-1-trigger")).to have_no_text("0000001-1")
    expect(page).to have_css("#stay-view-booking-1-panel", text: "Group booking", visible: :all)
    expect(page).to have_css("#stay-view-booking-1-panel", text: "Tour Group · 0000001-1", visible: :all)
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
    expect(page.find("#stay-view-booking-1-trigger")).to have_no_text("Checked in")
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

  it "flags smoking and pet restrictions as icon-only circular badges" do
    restricted_room = room.with(smoking_allowed: false, pets_allowed: false)
    render_inline(HotelPortal::StayView::RoomSummary.new(
      room: restricted_room,
      actions: [ { href: "/rooms/101", icon: "sparkles", label: "Change status" } ]
    ))

    expect(page).to have_css("[data-slot='stay-view-room-summary']", text: "101")
    expect(page).to have_no_css("[data-slot='stay-view-room-summary']", text: room.room_type_name)
    expect(page).to have_css("[data-slot='stay-view-room-summary'] > .w-full.justify-between")
    expect(page).to have_css(".panel-badge-circular[role='img'][aria-label='No smoking'][tabindex='0']")
    expect(page).to have_css(".panel-badge-circular[role='img'][aria-label='No pets'][tabindex='0']")
    expect(page).to have_css("##{room.dom_id}-smoking-tooltip[role='tooltip']", text: "No smoking", visible: :all)
    expect(page).to have_css("##{room.dom_id}-pets-tooltip[role='tooltip']", text: "No pets", visible: :all)
    expect(page).to have_css("##{room.dom_id}-actions-trigger svg", count: 1)
  end

  it "hides amenity badges when smoking and pets are both permitted" do
    permissive_room = room.with(smoking_allowed: true, pets_allowed: true)
    render_inline(HotelPortal::StayView::RoomSummary.new(room: permissive_room))

    expect(page).to have_no_css("[aria-label='Room amenities']")
    expect(page).to have_no_css(".panel-badge-circular[role='img']")
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
                  href: "/bookings/1/edit-stay",
                  icon: "pen-line",
                  label: "Edit stay & rate",
                  data: { turbo_frame: "booking_action_sheet" }
                }
              ]
            }
          ]
        },
        { href: "/rooms/101/status", icon: "sparkles", label: "Change room status" }
      ]
    ))

    expect(page).to have_css("#room-101-bookings[aria-label='Booking'] #room-101-booking-1[aria-label='Jack']", visible: :all)
    expect(page).to have_css("#room-101-booking-1 a[data-turbo-frame='booking_action_sheet']", text: "Edit stay & rate", visible: :all)
    expect(page).to have_css("##{room.dom_id}-actions-menu > a", text: "Change room status", visible: :all)
  end

  it "renders a static operational-status badge" do
    render_inline(HotelPortal::StayView::OperationalStatusBadge.new(
      room:,
      status: :occupied,
      reference_date: Date.new(2026, 7, 18)
    ))

    expect(page).to have_css(
      "[data-slot='stay-view-operational-status'][data-status='occupied']" \
      "[aria-label='Operational state: Occupied']",
      text: "Occupied"
    )
    expect(page).to have_no_css("button")
  end

  it "uses the configured semantic variant for every room-card state" do
    expected = {
      vacant: "success", arrival: "info", occupied: "primary", departure: "neutral",
      turnover: "warning", blocked: "destructive"
    }

    expected.each do |status, variant|
      render_inline(HotelPortal::StayView::OperationalStatusBadge.new(
        room:,
        status:,
        reference_date: Date.new(2026, 7, 18)
      ))

      expect(page).to have_css("[data-status='#{status}'][data-variant='#{variant}']")
    end
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
