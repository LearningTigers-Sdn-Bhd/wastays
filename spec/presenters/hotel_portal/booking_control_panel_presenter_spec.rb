# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingControlPanelPresenter do
  subject(:presenter) { described_class.new(booking) }

  let(:hotel) { create(:hotel, status: "approved") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      confirmation_token: "BK-CONTROL-1",
      reservation_number: 31,
      guest_name: "Fallback Guest",
      source: "booking_com"
    )
  end

  describe "booking details" do
    it "exposes references, established status labels, stay dates, and source" do
      booking.update_column(:status, "completed")

      expect(presenter.booking_id).to eq(booking.id)
      expect(presenter.booking_reference).to eq(booking.formatted_reservation_number)
      expect(presenter.status_label).to eq("Checked out")
      expect(presenter.check_in_date).to eq(booking.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(presenter.check_out_date).to eq(booking.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(presenter.source_label).to eq("Booking Com")
    end

    it "uses the group booking number in the summary when viewing a child booking" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      expect(presenter.summary_subtitle).to eq("Booking No. #{group.formatted_reservation_number}")
      expect(presenter.summary_items).to include([ "Booking No.", group.formatted_reservation_number ])
    end

    it "exposes group summary actions from eligible child booking statuses" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "completed")
      checkout_child = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      checkout_child.update_column(:status, "checked_in")
      cancel_child = create(:booking, hotel: hotel, group_booking: group, group_position: 3)
      cancel_child.update_column(:status, "confirmed")

      actions = presenter.group_summary_actions

      expect(actions.map(&:label)).to include("Check-in", "Check-out", "Cancel")
      expect(actions.find { |action| action.key == :check_out }).to have_attributes(offcanvas_variant: "fullscreen-bottom", icon: "log-out", target_booking: checkout_child)
    end

    it "does not expose group summary actions for standalone bookings" do
      booking.update_column(:status, "checked_in")

      expect(presenter.group_summary_actions).to be_empty
    end

    it "exposes edit and undo check-in group summary actions for checked-in children" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "confirmed")
      checked_in_child = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      checked_in_child.update_column(:status, "checked_in")

      actions = presenter.group_summary_actions

      expect(actions.map(&:label)).to include("Edit Check-In", "Undo Check-in")
      expect(actions.find { |action| action.key == :edit_check_in }).to have_attributes(tone: :neutral, icon: "pencil", offcanvas_variant: "right", target_booking: checked_in_child)
      expect(actions.find { |action| action.key == :undo_check_in }).to have_attributes(tone: :warning, icon: "rotate-ccw", offcanvas_variant: "right", target_booking: checked_in_child)
    end

    it "exposes standalone summary actions from the booking status" do
      booking.update_column(:status, "checked_in")

      actions = presenter.summary_actions

      expect(actions.map(&:label)).to eq([ "Check-out", "Edit Check-In", "Undo Check-in" ])
      expect(actions.map(&:target_booking)).to all(eq(booking))
      expect(actions.find { |action| action.key == :undo_check_in }).to have_attributes(icon: "rotate-ccw", offcanvas_variant: "right")
    end

    it "does not expose standalone summary actions for completed bookings" do
      booking.update_column(:status, "completed")

      expect(presenter.summary_actions).to be_empty
    end

    it "exposes group-aware actions on the group overview" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")

      overview_presenter = described_class.new(booking, params: { scope: "group" })

      expect(overview_presenter.group_summary_actions.map(&:label)).to include("Check-out")
    end

    it "returns compact status badge metadata for group child bookings" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checkout_required")

      expect(presenter.status_badge_for_booking_id(booking.id)).to eq(label: "Checkout due", tone: "orange")
    end
  end

  describe "primary guest" do
    it "uses the primary booking guest" do
      primary_guest = create(:guest, name: "Primary Guest")
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Additional Guest"), is_primary: false)
      create(:booking_guest, booking: booking, guest: primary_guest, is_primary: true)

      expect(presenter.primary_guest_name).to eq("Primary Guest")
    end

    it "falls back to the booking guest name" do
      expect(presenter.primary_guest_name).to eq("Fallback Guest")
    end
  end

  describe "rooms" do
    it "totals booked quantity and exposes room number and type rows" do
      deluxe = create(:room_type, hotel: hotel, name: "Deluxe King")
      family = create(:room_type, hotel: hotel, name: "Family Suite")
      create(:booking_room, booking: booking, room_type: deluxe, room_number: "101", quantity: 1)
      create(:booking_room, booking: booking, room_type: family, room_number: nil, quantity: 2)

      expect(presenter.room_count).to eq(3)
      expect(presenter.rooms.map(&:to_h)).to eq(
        [
          { room_number: "101", room_type: "Deluxe King" },
          { room_number: "Unassigned", room_type: "Family Suite" }
        ]
      )
    end

    it "handles bookings without rooms" do
      expect(presenter.room_count).to eq(0)
      expect(presenter.rooms).to be_empty
    end
  end

  describe "room-rate rows" do
    it "renders one row per room night and marks missing rates without using folio postings" do
      booking.update!(check_in: Time.zone.local(2026, 7, 10, 15), check_out: Time.zone.local(2026, 7, 13, 11))
      create(
        :booking_room,
        booking: booking,
        room_number: "201",
        nightly_rate_snapshot: {
          "2026-07-10" => { "price" => "180.00" },
          "2026-07-11" => { "price" => "190.00" }
        }
      )

      rows = described_class.new(booking.reload).room_rate_rows

      expect(rows.size).to eq(3)
      expect(rows.map(&:room)).to all(eq("201"))
      expect(rows.map(&:nightly_rate)).to eq([ "MYR 180.00", "MYR 190.00", "Rate unavailable" ])
      expect(rows.map(&:rate_missing)).to eq([ false, false, true ])
    end

    it "renders every room and night combination" do
      booking.update!(check_in: Time.zone.local(2026, 7, 10, 15), check_out: Time.zone.local(2026, 7, 12, 11))
      create(:booking_room, booking: booking, room_number: "201")
      create(:booking_room, booking: booking, room_number: "202")

      rows = described_class.new(booking.reload).room_rate_rows

      expect(rows.size).to eq(4)
      expect(rows.map(&:room)).to contain_exactly("201", "201", "202", "202")
    end

    it "shows snapshot rates when booking dates are invalid" do
      booking.update!(check_in: Time.zone.local(2026, 6, 30, 15), check_out: Time.zone.local(2026, 6, 30, 12))
      create(
        :booking_room,
        booking: booking,
        room_number: "107",
        nightly_rate_snapshot: { "2026-06-30" => { "price" => "740.0" } }
      )

      snapshot_presenter = described_class.new(booking.reload)
      row = snapshot_presenter.room_rate_rows.sole

      expect(row).to have_attributes(date: Date.new(2026, 6, 30), room: "107", nightly_rate: "MYR 740.00", rate_missing: false)
      expect(snapshot_presenter.room_rate_empty_message).to be_nil
    end

    it "includes snapshot dates outside the expected stay range" do
      booking.update!(check_in: Time.zone.local(2026, 7, 10, 15), check_out: Time.zone.local(2026, 7, 12, 11))
      create(:booking_room, booking: booking, nightly_rate_snapshot: { "2026-07-15" => { "price" => "225.0" } })

      rows = described_class.new(booking.reload).room_rate_rows

      expect(rows.map(&:date)).to eq([ Date.new(2026, 7, 10), Date.new(2026, 7, 11), Date.new(2026, 7, 15) ])
      expect(rows.map(&:nightly_rate)).to eq([ "Rate unavailable", "Rate unavailable", "MYR 225.00" ])
    end

    it "provides explicit empty messages for missing rooms and invalid dates" do
      expect(presenter.room_rate_empty_message).to eq("No room is attached to this booking.")

      create(:booking_room, booking: booking)
      booking.update!(check_out: booking.check_in)

      expect(described_class.new(booking.reload).room_rate_empty_message).to eq("No recorded room rates are available for this booking.")
    end
  end

  describe "left rail modes" do
    it "keeps booking context visible for ordinary standalone tabs" do
      %w[booking_details billing_preferences security_deposits source_details room_and_rate housekeeping_requests].each do |tab|
        tab_presenter = described_class.new(booking, params: { tab: tab })

        expect(tab_presenter.left_rail_mode).to eq("booking_context")
        expect(tab_presenter.layout_mode).to eq("left_and_center")
      end
    end

    it "uses entity context only for folio and guest tabs" do
      expect(described_class.new(booking, params: { tab: "folio_operations" }).left_rail_mode).to eq("folio_tree")
      expect(described_class.new(booking, params: { tab: "guest_details" }).left_rail_mode).to eq("guest_tree")
      expect(described_class.new(booking, params: { tab: "audit_trails" }).left_rail_mode).to eq("booking_context")
    end

    it "uses child-booking context for ordinary grouped tabs" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      room_presenter = described_class.new(booking, params: { tab: "room_and_rate" })
      billing_presenter = described_class.new(booking, params: { tab: "billing_preferences" })
      deposits_presenter = described_class.new(booking, params: { tab: "security_deposits" })
      requests_presenter = described_class.new(booking, params: { tab: "housekeeping_requests" })

      expect(room_presenter).to have_attributes(left_rail_mode: "child_booking_tree", layout_mode: "left_and_center")
      expect(billing_presenter).to have_attributes(left_rail_mode: "child_booking_tree", billing_scope: "group")
      expect(deposits_presenter).to have_attributes(left_rail_mode: "child_booking_tree", layout_mode: "left_and_center")
      expect(requests_presenter).to have_attributes(left_rail_mode: "child_booking_tree", layout_mode: "left_and_center")
    end

    it "uses tab-specific titles for grouped booking rails" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      expected_titles = {
        "booking_details" => "Bookings / Details",
        "security_deposits" => "Bookings / Deposits",
        "billing_preferences" => "Bookings / Billing",
        "room_and_rate" => "Bookings / Room Rate",
        "source_details" => "Bookings / Sources",
        "housekeeping_requests" => "Bookings / Requests",
        "audit_trails" => "Bookings / Audit Trails"
      }

      expected_titles.each do |tab, title|
        expect(described_class.new(booking, params: { tab: tab }).left_rail_title).to eq(title)
      end
    end

    it "uses singular tab-specific titles for standalone booking rails" do
      expected_titles = {
        "booking_details" => "Booking / Details",
        "security_deposits" => "Booking / Deposits",
        "billing_preferences" => "Booking / Billing",
        "room_and_rate" => "Booking / Room Rate",
        "source_details" => "Booking / Sources",
        "housekeeping_requests" => "Booking / Requests",
        "audit_trails" => "Booking / Audit Trails"
      }

      expected_titles.each do |tab, title|
        expect(described_class.new(booking, params: { tab: tab }).left_rail_title).to eq(title)
      end
    end

    it "uses the shared booking-row shape for standalone context" do
      booking.update!(guest_name: "Standalone Guest")
      room_type = create(:room_type, hotel: hotel, name: "Executive Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      row = described_class.new(booking, params: { tab: "booking_details" }).standalone_booking_rows.sole

      expect(row).to have_attributes(label: "Room 208", description: "Executive Suite - Standalone Guest", active: true)
      expect(row.href).to include("tab=booking_details")
    end

    it "builds concise room and guest rows with safe fallbacks" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, guest_name: "Booking Guest")
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "105")
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Primary Guest"), is_primary: true)
      fallback = create(:booking, hotel: hotel, group_booking: group, group_position: 2, guest_name: "Fallback Guest")

      rows = described_class.new(booking, params: { tab: "booking_details" }).child_booking_rows

      expect(rows.first).to have_attributes(label: "Room 105", description: "Garden Suite - Primary Guest")
      expect(rows.second).to have_attributes(label: "Unassigned room", description: "Room type unavailable - Fallback Guest")
      expect(rows.first.description).not_to include("Booking No.", "MYR")
    end

    it "uses booking-first titles for grouped entity rails" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      expect(described_class.new(booking, params: { tab: "folio_operations" }).left_rail_title).to eq("Bookings / Folios")
      expect(described_class.new(booking, params: { tab: "guest_details" }).left_rail_title).to eq("Bookings / Guests")
    end

    it "registers the adjusted tab order and Requests label" do
      expect(presenter.tabs.map { |tab| [ tab.key, tab.label ] }).to eq([
        [ "booking_details", "Booking Details" ],
        [ "folio_operations", "Folio Operations" ],
        [ "security_deposits", "Security Deposits" ],
        [ "billing_preferences", "Billing Preferences" ],
        [ "guest_details", "Guest Details" ],
        [ "room_and_rate", "Room & Rate" ],
        [ "source_details", "Source Details" ],
        [ "housekeeping_requests", "Requests" ],
        [ "audit_trails", "Audit Trails" ]
      ])
    end

    it "separates warning alerts from true editor drawers" do
      alert_presenter = described_class.new(booking, params: { tab: "room_and_rate", alert_action: "change_rate" })
      invalid_alert_presenter = described_class.new(booking, params: { tab: "room_and_rate", alert_action: "change_room" })
      removed_drawer_presenter = described_class.new(booking, params: { tab: "billing_preferences", drawer: "billing" })
      drawer_presenter = described_class.new(booking, params: { tab: "folio_operations", drawer: "deposit" })

      expect(alert_presenter).to have_attributes(alert_action: "change_rate", alert_open?: true, layout_mode: "left_and_center", show_right_drawer?: false)
      expect(invalid_alert_presenter).to have_attributes(alert_action: nil, alert_open?: false)
      expect(removed_drawer_presenter).to have_attributes(layout_mode: "left_and_center", show_right_drawer?: false)
      expect(drawer_presenter).to have_attributes(layout_mode: "left_center_right", show_right_drawer?: true)
    end
  end

  describe "context tree groups" do
    it "groups room context by room type and room number" do
      deluxe = create(:room_type, hotel: hotel, name: "Deluxe King")
      family = create(:room_type, hotel: hotel, name: "Family Suite")
      create(:booking_room, booking: booking, room_type: deluxe, room_number: "101", quantity: 1)
      create(:booking_room, booking: booking, room_type: family, room_number: "201", quantity: 1)

      groups = presenter.room_tree_groups

      expect(groups.map(&:label)).to contain_exactly("Deluxe King", "Family Suite")
      expect(groups.flat_map(&:rows).map(&:label)).to contain_exactly("101", "201")
    end

    it "groups folio context as group folios and room-type room folios" do
      room_type = create(:room_type, hotel: hotel, name: "Family Room")
      room = create(:booking_room, booking: booking, room_type: room_type, room_number: "301", quantity: 1)
      group_folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Group Folio", booking_room: nil)
      room_folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Room Guest Folio", booking_room: room)
      corporate_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Corporate Folio", booking_room: nil)

      tab_presenter = described_class.new(booking, params: { tab: "folio_operations", folio_id: room_folio.id })

      expect(tab_presenter.group_folio_tree_rows.map(&:label)).to contain_exactly(group_folio.display_name, corporate_folio.display_name)
      expect(tab_presenter.folio_room_type_groups.first[:label]).to eq("Family Room")
      expect(tab_presenter.folio_room_type_groups.first[:room_groups].first[:label]).to eq("301")
      expect(tab_presenter.folio_room_type_groups.first[:room_groups].first[:rows].map(&:label)).to eq([ "Room Guest Folio" ])
    end

    it "builds grouped folio hierarchy as child bookings with folios" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, confirmation_token: "B-10031", reservation_number: 31)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "B-10032", reservation_number: 32)
      current_room = create(:booking_room, booking: booking, room_number: "101")
      sibling_room = create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Guest One"), is_primary: true)
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Guest Two"), is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")
      create(:booking_folio, booking: sibling, hotel: hotel, name: "Corporate Folio")

      tab_presenter = described_class.new(booking, params: { tab: "folio_operations" }, hotel: hotel)

      expect(tab_presenter.grouped_folio_tree_groups.map(&:label)).to include(
        "Room 101",
        "Room 102"
      )
      expect(tab_presenter.grouped_folio_tree_groups.map(&:description)).to include(
        "#{current_room.room_type.name} - Guest One",
        "#{sibling_room.room_type.name} - Guest Two"
      )
      expect(tab_presenter.grouped_folio_tree_groups.flat_map(&:rows).map(&:label)).to include("Guest Folio", "Corporate Folio")
      expect(tab_presenter.grouped_folio_tree_groups.flat_map(&:rows).map(&:description)).to include(
        "#{booking.booking_folios.first.folio_reference_display} · #{booking.booking_folios.first.payer_display_label}",
        "#{sibling.booking_folios.first.folio_reference_display} · #{sibling.booking_folios.first.payer_display_label}"
      )
    end

    it "leaves every child folio inactive while group scope is active" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      current_folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:booking_folio, booking: sibling, hotel: hotel)

      group_presenter = described_class.new(
        booking,
        params: { tab: "folio_operations", scope: "group", folio_id: current_folio.id },
        hotel: hotel
      )

      expect(group_presenter).to be_group_overview
      expect(group_presenter.grouped_folio_tree_groups.flat_map(&:rows)).to all(satisfy { |row| !row.active })
    end

    it "builds grouped guest hierarchy as child bookings with guests" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Primary One"), is_primary: true)
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Primary Two"), is_primary: true)

      tab_presenter = described_class.new(booking, params: { tab: "guest_details" }, hotel: hotel)

      expect(tab_presenter.grouped_guest_tree_groups.map(&:label)).to contain_exactly("Unassigned room", "Unassigned room")
      expect(tab_presenter.grouped_guest_tree_groups.map(&:description)).to contain_exactly(
        "Room type unavailable - Primary One",
        "Room type unavailable - Primary Two"
      )
      expect(tab_presenter.grouped_guest_tree_groups.flat_map(&:rows).map(&:label)).to contain_exactly("Primary One", "Primary Two")
    end

    it "uses room and guest identity for standalone folio and guest groups" do
      room_type = create(:room_type, hotel: hotel, name: "Executive Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Standalone Guest"), is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel)

      folio_group = described_class.new(booking, params: { tab: "folio_operations" }).booking_folio_tree_groups.sole
      guest_group = described_class.new(booking, params: { tab: "guest_details" }).guest_tree_groups.sole

      expect(folio_group).to have_attributes(label: "Room 208", description: "Executive Suite - Standalone Guest")
      expect(guest_group).to have_attributes(label: "Room 208", description: "Executive Suite - Standalone Guest")
    end

    it "opens only the current empty booking group when room labels are duplicated" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      tab_presenter = described_class.new(booking, params: { tab: "folio_operations" }, hotel: hotel)
      groups = tab_presenter.grouped_folio_tree_groups

      expect(groups.map(&:label)).to eq([ "Unassigned room", "Unassigned room" ])
      expect(groups.map { |tree_group| tab_presenter.booking_tree_group_open?(tree_group) }).to eq([ true, false ])
    end

    it "summarizes security deposits" do
      create(:deposit, booking: booking, hotel: hotel, amount: 250, status: "held")

      tab_presenter = described_class.new(booking, params: { tab: "security_deposits" })

      expect(tab_presenter.held_security_deposit_total).to eq(250.to_d)
      expect(tab_presenter.security_deposit_status_label).to eq("Held")
      expect(tab_presenter.security_deposit_rows.first[:amount]).to eq("MYR 250.00")
    end

    it "builds billing party rows from booking billing parties" do
      guest = create(:guest, name: "Aina Rahman")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      guest_party = booking_guest.booking_billing_party
      guest_folio = create(:booking_folio, booking: booking, hotel: hotel, booking_billing_party: guest_party)
      company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: company_party, hotel_corporate_account: company_party.hotel_corporate_account)

      rows = described_class.new(booking, params: { tab: "billing_preferences" }).billing_party_rows

      expect(rows.map(&:label)).to include("Aina Rahman", company_party.display_name)
      expect(rows.find { |row| row.record == guest_party }).to have_attributes(kind: "Guest", role: "Primary guest", folio_count: 1, folio_labels: [ guest_folio.display_name ])
      expect(rows.find { |row| row.record == company_party }).to have_attributes(kind: "Company", role: "Company / Government account", folio_count: 1, folio_labels: [ company_folio.display_name ])
    end

    it "groups folio-window billing party options for guests and companies" do
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Aina Rahman"), is_primary: true)
      create(:booking_billing_party, :company, booking: booking, hotel: hotel)

      groups = described_class.new(booking, params: { tab: "folio_operations" }).folio_window_billing_party_option_groups

      expect(groups.keys).to include("Guests", "Companies / Government")
      expect(groups["Guests"].map(&:label)).to include("Aina Rahman")
      expect(groups["Companies / Government"].first.description).to include("Company / Government account")
    end

    it "consolidates housekeeping and complaints into kanban columns" do
      create(:housekeeping_request, booking: booking, request_details: "Towels", status: "pending")
      create(:complaint_request, booking: booking, complaint_details: "Water heater", status: "resolved")

      tab_presenter = described_class.new(booking, params: { tab: "housekeeping_requests" })

      expect(tab_presenter.requests_kanban_columns.find { |column| column.key == "new" }.cards.map(&:details)).to include("Towels")
      expect(tab_presenter.requests_kanban_columns.find { |column| column.key == "completed" }.cards.map(&:details)).to include("Water heater")
    end

    it "masks safe guest display values" do
      guest = create(:guest, name: "Hanami Ume", email: "hanami@mail.com", phone: "+60123451234", government_id: "P4821")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      display = described_class.new(booking, params: { tab: "guest_details", booking_guest_id: booking_guest.id }).guest_display(booking_guest)

      expect(display[:email]).to eq("h***@mail.com")
      expect(display[:phone]).to end_with("1234")
      expect(display[:government_id]).to eq("••••4821")
    end

    it "keeps audit filters out of the context rail" do
      expect(described_class.new(booking, params: { tab: "audit_trails" })).to have_attributes(
        left_rail_mode: "booking_context",
        left_rail_title: "Booking / Audit Trails"
      )
    end

    it "marks default folio active only for folio operations" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      folio_presenter = described_class.new(booking, params: { tab: "folio_operations" })
      room_presenter = described_class.new(booking, params: { tab: "booking_details" })

      expect(folio_presenter.folio_tree_rows.find { |row| row.id == folio.id }).to have_attributes(active: true)
      expect(folio_presenter.folio_tree_rows.find { |row| row.id == folio.id }.href).not_to include("folio_tab")
      expect(room_presenter.folio_tree_rows.find { |row| row.id == folio.id }).to have_attributes(active: false)
    end
  end
end
