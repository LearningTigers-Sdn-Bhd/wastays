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
      guest_name: "Fallback Guest",
      source: "booking_com"
    )
  end

  describe "booking details" do
    it "exposes references, established status labels, stay dates, and source" do
      booking.update_column(:status, "completed")

      expect(presenter.booking_id).to eq(booking.id)
      expect(presenter.booking_reference).to eq("BK-CONTROL-1")
      expect(presenter.status_label).to eq("Checked out")
      expect(presenter.check_in_date).to eq(booking.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(presenter.check_out_date).to eq(booking.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(presenter.source_label).to eq("Booking Com")
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
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
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
      drawer_presenter = described_class.new(booking, params: { tab: "billing_preferences", drawer: "billing" })

      expect(alert_presenter).to have_attributes(alert_action: "change_rate", alert_open?: true, layout_mode: "left_and_center", show_right_drawer?: false)
      expect(invalid_alert_presenter).to have_attributes(alert_action: nil, alert_open?: false)
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
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, confirmation_token: "B-10031")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "B-10032")
      current_room = create(:booking_room, booking: booking, room_number: "101")
      sibling_room = create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")
      create(:booking_folio, booking: sibling, hotel: hotel, name: "Corporate Folio")

      tab_presenter = described_class.new(booking, params: { tab: "folio_operations" }, hotel: hotel)

      expect(tab_presenter.grouped_folio_tree_groups.map(&:label)).to include("B-10031", "B-10032")
      expect(tab_presenter.grouped_folio_tree_groups.map(&:description)).to include(
        "#{current_room.room_type.name} · Room 101",
        "#{sibling_room.room_type.name} · Room 102"
      )
      expect(tab_presenter.grouped_folio_tree_groups.flat_map(&:rows).map(&:label)).to include("Guest Folio", "Corporate Folio")
    end

    it "builds grouped guest hierarchy as child bookings with guests" do
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Primary One"), is_primary: true)
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Primary Two"), is_primary: true)

      tab_presenter = described_class.new(booking, params: { tab: "guest_details" }, hotel: hotel)

      expect(tab_presenter.grouped_guest_tree_groups.flat_map(&:rows).map(&:label)).to contain_exactly("Primary One", "Primary Two")
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
        left_rail_title: "Booking"
      )
    end

    it "marks default folio active only for folio operations" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      folio_presenter = described_class.new(booking, params: { tab: "folio_operations" })
      room_presenter = described_class.new(booking, params: { tab: "booking_details" })

      expect(folio_presenter.folio_tree_rows.find { |row| row.id == folio.id }).to have_attributes(active: true)
      expect(room_presenter.folio_tree_rows.find { |row| row.id == folio.id }).to have_attributes(active: false)
    end
  end
end
