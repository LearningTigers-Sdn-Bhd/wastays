# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Bookings::WorkspacePresenter do
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

  def enable_audit_feature
    hotel.update!(plan: create(:plan))
    feature = create(:feature, feature_group: create(:feature_group), slug: "full_audit_trail")
    create(:plan_feature, plan: hotel.plan, feature: feature, enabled: true)
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

    it "uses group identity in the header when viewing a child booking" do
      group = create(:group_booking, hotel: hotel, name: "Iskandar Family")
      booking.update!(group_booking: group, group_position: 1)

      expect(presenter.header_title).to eq(group.formatted_reservation_number)
      expect(presenter.header_party_line).to eq("Iskandar Family")
      expect(presenter.header_outstanding_balance).to eq(presenter.money(presenter.group_total_balance))
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

    it "defaults grouped booking details to the group overview while preserving explicit child scope" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      default_presenter = described_class.new(booking, params: { tab: "booking_details" })
      child_presenter = described_class.new(booking, params: { tab: "booking_details", scope: "booking" })

      expect(default_presenter).to be_group_overview
      expect(child_presenter).not_to be_group_overview
      expect(child_presenter.tab_path("room_and_rate")).to include("scope=booking")
      expect(child_presenter.tab_path("folio_operations")).not_to include("scope=booking")
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
    it "exposes one room row for each child of a multi-room group booking" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      deluxe = create(:room_type, hotel: hotel, name: "Deluxe King")
      family = create(:room_type, hotel: hotel, name: "Family Suite")
      create(:booking_room, booking: booking, room_type: deluxe, room_number: "101")
      create(:booking_room, booking: sibling, room_type: family, room_number: nil)
      sibling_presenter = described_class.new(sibling)

      expect([ presenter.room_count, sibling_presenter.room_count ]).to eq([ 1, 1 ])
      expect((presenter.rooms + sibling_presenter.rooms).map(&:to_h)).to eq(
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
      group = create(:group_booking, hotel: hotel)
      booking.update!(
        check_in: Time.zone.local(2026, 7, 10, 15),
        check_out: Time.zone.local(2026, 7, 12, 11),
        group_booking: group,
        group_position: 1
      )
      sibling = create(
        :booking,
        hotel: hotel,
        check_in: booking.check_in,
        check_out: booking.check_out,
        group_booking: group,
        group_position: 2
      )
      create(:booking_room, booking: booking, room_number: "201")
      create(:booking_room, booking: sibling, room_number: "202")

      rows = described_class.new(booking.reload).room_rate_rows + described_class.new(sibling.reload).room_rate_rows

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

  describe "booking header" do
    it "summarizes a standalone booking" do
      expect(presenter.header_title).to eq(booking.formatted_reservation_number)
      expect(presenter.header_party_line).to eq(presenter.primary_guest_name)
      expect(presenter.stay_dates_vary?).to be(false)
      expect(presenter.header_stay_line).to include("night")
      expect(presenter.header_outstanding_balance).to eq(presenter.money(presenter.total_balance))
    end

    it "maps booking status into a header badge" do
      booking.update_column(:status, "checked_in")

      expect(presenter.header_status_badge).to eq({ label: "In house", variant: :success })
    end

    it "flags mixed child stay dates for a group overview" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2,
                       check_in: booking.check_in, check_out: booking.check_out + 3.days)
      group_presenter = described_class.new(booking, params: { scope: "group" })

      expect(group_presenter.stay_dates_vary?).to be(true)
      expect(group_presenter.group_stay_summary).to eq("Stay dates vary")
      expect(group_presenter.header_stay_line).to include("Stay dates vary")
      expect(group_presenter.header_title).to eq(group.formatted_reservation_number)
    end

    it "shows a shared range when group child dates match" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2,
                       check_in: booking.check_in, check_out: booking.check_out)
      group_presenter = described_class.new(booking, params: { scope: "group" })

      expect(group_presenter.stay_dates_vary?).to be(false)
      expect(group_presenter.group_stay_summary).not_to eq("Stay dates vary")
    end

    it "shows partially in house for mixed child lifecycle statuses" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed")

      expect(presenter.header_status_badge).to eq(label: "Partially in house", variant: :warning)
    end

    it "keeps both the group name and organizer when they differ" do
      organizer = create(:guest, name: "Jane Tan")
      group = create(:group_booking, hotel: hotel, name: "Iskandar Family", organizer_guest: organizer)
      booking.update!(group_booking: group, group_position: 1)

      expect(presenter.header_party_line).to eq("Iskandar Family · Organizer — Jane Tan")
    end

    it "drops the group name when it only repeats the organizer" do
      organizer = create(:guest, name: "Katsuragi Lilja")
      group = create(:group_booking, hotel: hotel, name: "Katsuragi Lilja group", organizer_guest: organizer)
      booking.update!(group_booking: group, group_position: 1)

      expect(presenter.header_party_line).to eq("Organizer — Katsuragi Lilja")
    end

    it "falls back to the group name when no organizer is assigned" do
      group = create(:group_booking, hotel: hotel, name: "Iskandar Family", organizer_guest: nil)
      booking.update!(group_booking: group, group_position: 1)

      expect(presenter.header_party_line).to eq("Iskandar Family")
    end

    it "breaks the group status badge down per room in group_position order" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed")

      rows = presenter.header_status_rows

      expect(rows.size).to eq(2)
      expect(rows.first[:badge]).to eq(label: "In house", variant: :success)
      expect(rows.last[:badge]).to eq(label: "Confirmed", variant: :info)
      expect(rows.map { |row| row[:room] }).to all(be_present)
      expect(rows.map { |row| row[:room_type] }).to all(be_present)
    end

    it "returns no status breakdown for a standalone booking" do
      expect(presenter.header_status_rows).to eq([])
    end

    it "handles partially missing group dates" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      child = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      child.check_in = nil
      child.check_out = nil
      allow(presenter).to receive(:child_bookings).and_return([ booking, child ])

      expect(presenter.group_stay_summary).to eq("Some stay dates unavailable")
      expect { presenter.header_stay_line }.not_to raise_error
    end

    it "preserves group identity on concrete folio and guest destinations" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)

      %w[folio_operations guest_details].each do |tab|
        entity_presenter = described_class.new(booking, params: { tab: tab }, hotel: hotel)

        expect(entity_presenter.header_title).to eq(group.formatted_reservation_number)
        expect(entity_presenter.header_party_line).to eq("Conference Group")
      end
    end
  end

  describe "group stay date helpers" do
    let(:group_presenter) do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2,
                       check_in: booking.check_in + 2.days, check_out: booking.check_out + 3.days)
      described_class.new(booking, params: { scope: "group" }, hotel: hotel)
    end

    it "returns distinct, sorted arrival and departure dates" do
      expect(group_presenter.group_arrival_dates.size).to eq(2)
      expect(group_presenter.group_departure_dates.size).to eq(2)
      expect(group_presenter.group_arrival_dates).to eq(group_presenter.group_arrival_dates.sort)
      expect(group_presenter.group_departure_dates).to eq(group_presenter.group_departure_dates.sort)
    end

    it "builds a variation notice naming arrivals and departures" do
      notice = group_presenter.group_stay_variation_notice

      expect(notice).to start_with("Arrivals occur on")
      expect(notice).to include("Departures occur on")
    end

    it "omits the variation notice when child dates match" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2,
                       check_in: booking.check_in, check_out: booking.check_out)
      matched_presenter = described_class.new(booking, params: { scope: "group" }, hotel: hotel)

      expect(matched_presenter.group_stay_variation_notice).to be_nil
    end

    it "describes known dates without producing empty clauses when group dates are incomplete" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, check_in: booking.check_in + 2.days)
      booking.check_out = nil
      sibling.check_out = nil
      incomplete_presenter = described_class.new(booking, params: { scope: "group" }, hotel: hotel)
      allow(incomplete_presenter).to receive(:child_bookings).and_return([ booking, sibling ])

      notice = incomplete_presenter.group_stay_variation_notice

      expect(notice).to include("Arrivals occur on", "Some stay dates are unavailable.")
      expect(notice).not_to include("Departures occur on .")
    end

    it "reports incomplete dates even when the known dates do not vary" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(
        :booking,
        hotel: hotel,
        group_booking: group,
        group_position: 2,
        check_in: booking.check_in,
        check_out: booking.check_out
      )
      sibling.check_out = nil
      incomplete_presenter = described_class.new(booking, params: { scope: "group" }, hotel: hotel)
      allow(incomplete_presenter).to receive(:child_bookings).and_return([ booking, sibling ])

      expect(incomplete_presenter.stay_dates_vary?).to be(false)
      expect(incomplete_presenter.group_stay_variation_notice).to include("Some stay dates are unavailable.")
    end
  end

  describe "group overview rows" do
    it "orders child bookings by group position and exposes arrival and departure separately" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(
        :booking,
        hotel: hotel,
        group_booking: group,
        group_position: 1,
        check_in: booking.check_in - 2.days,
        check_out: booking.check_out - 1.day
      )

      rows = described_class.new(booking.reload, params: { scope: "group" }, hotel: hotel).stay_rows

      expect(rows.map { |row| row[:booking] }).to eq([ first_child, booking ])
      expect(rows.first).to include(
        arrival: first_child.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"),
        departure: first_child.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y")
      )
      expect(rows.first).not_to have_key(:stay)
      expect(rows.first).not_to have_key(:rate_plan)
    end

    it "yields exactly one stay row for a standalone booking" do
      rows = described_class.new(booking.reload, hotel: hotel).stay_rows

      expect(rows.size).to eq(1)
      expect(rows.first[:booking]).to eq(booking)
      expect(rows.first[:nights]).to eq((booking.check_out.to_date - booking.check_in.to_date).to_i)
      expect(rows.first[:status]).to include(:label, :variant)
    end

    it "labels pax with children only when there are children" do
      booking.update!(adults: 2, children: 0)
      expect(described_class.new(booking.reload, hotel: hotel).stay_rows.first[:pax]).to eq("2A")

      booking.update!(adults: 2, children: 1)
      expect(described_class.new(booking.reload, hotel: hotel).stay_rows.first[:pax]).to eq("2A · 1C")
    end
  end

  describe "reference rows" do
    def format_source_for(value)
      value.to_s.presence&.tr("_", " ")&.titleize || "—"
    end

    it "reads reservation-level references from the booking when standalone" do
      booking.update!(external_reference: "OTA-99", channel_manager_reference: "CM-77")

      pairs = described_class.new(booking.reload, hotel: hotel).reservation_reference_pairs

      expect(pairs).to eq([ [ "External Reference", "OTA-99" ], [ "Channel Manager", "CM-77" ] ])
    end

    # SplitLegacyMultiRoom promotes these to the group and nulls them on the child, so group
    # context must read the group even though the child booking is the workspace root.
    it "reads reservation-level references from the group and adds the organizer" do
      organizer = create(:guest, name: "Jane Tan")
      group = create(:group_booking, hotel: hotel, organizer_guest: organizer,
                                     external_reference: "GRP-1", channel_manager_reference: "CM-1")
      booking.update!(group_booking: group, group_position: 1,
                      external_reference: nil, channel_manager_reference: nil)

      pairs = described_class.new(booking.reload, params: { scope: "group" }, hotel: hotel).reservation_reference_pairs

      expect(pairs).to eq([
        [ "External Reference", "GRP-1" ],
        [ "Channel Manager", "CM-1" ],
        [ "Organizer", "Jane Tan" ]
      ])
    end

    it "renders an em dash for every missing reservation-level reference" do
      pairs = described_class.new(booking.reload, hotel: hotel).reservation_reference_pairs

      expect(pairs.map(&:last)).to all(eq("—"))
    end

    it "yields one room-level reference row per booking with a shared source format" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1, source: "booking_com")
      create(:booking, hotel: hotel, group_booking: group, group_position: 2, source: "walk_in")

      rows = described_class.new(booking.reload, params: { scope: "group" }, hotel: hotel).booking_reference_rows

      expect(rows.size).to eq(3)
      expect(rows.first).to include(
        group: true,
        booking_number: group.formatted_reservation_number,
        confirmation_code: group.confirmation_token,
        receipt_number: group.formatted_receipt_number,
        invoice_number: "—",
        folio_account: "—",
        guest_registration: "—"
      )
      expect(rows.drop(1).map { |row| row[:source] }).to eq([ "Booking Com", "Walk In" ])
      expect(rows.drop(1).map { |row| row[:confirmation_code] }).to include(booking.confirmation_token)
      expect(rows.drop(1)).to all(satisfy { |row| !row.key?(:group) })
    end

    it "shows the invoice number once checkout has closed the primary folio" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)

      expect(described_class.new(booking.reload, hotel: hotel).booking_reference_rows.first[:invoice_number]).to eq("—")

      folio.update!(invoice_number: 512)

      expect(described_class.new(booking.reload, hotel: hotel).booking_reference_rows.first[:invoice_number])
        .to eq(booking.reload.formatted_invoice_number)
    end

    it "yields exactly one room-level reference row for a standalone booking" do
      rows = described_class.new(booking.reload, hotel: hotel).booking_reference_rows

      expect(rows.size).to eq(1)
      expect(rows.first[:booking]).to eq(booking)
      expect(rows.first).not_to have_key(:group)
    end
  end

  describe "billing party rows" do
    it "resolves an auto-created primary guest folio to the guest even without a billing party" do
      guest = create(:guest, name: "Katsuragi Lilja")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, is_primary: true,
                             payer_type: "guest", booking_billing_party: nil)

      rows = described_class.new(booking.reload, hotel: hotel).financial_party_rows

      expect(rows.size).to eq(1)
      expect(rows.first).to include(name: "Katsuragi Lilja", kind: "Guest", folio_count: 1)
    end

    # Current validation forbids a company folio without a corporate account, but legacy rows
    # like this exist, so the column is cleared directly to reproduce them.
    it "surfaces a legacy company folio with neither party nor corporate account as Unassigned" do
      folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: nil)
      folio.update_column(:hotel_corporate_account_id, nil)

      rows = described_class.new(booking.reload, hotel: hotel).financial_party_rows

      expect(rows.map { |row| row[:name] }).to include("Unassigned")
    end

    it "merges one company across group children into a single row" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      account = create(:hotel_corporate_account, hotel: hotel)

      [ booking, sibling ].each do |child|
        create(:booking_folio, :secondary, booking: child, hotel: hotel,
                               booking_billing_party: nil, hotel_corporate_account: account)
      end

      rows = described_class.new(booking.reload, params: { scope: "group" }, hotel: hotel).financial_party_rows
      company_rows = rows.select { |row| row[:kind] == "Company" }

      expect(company_rows.size).to eq(1)
      expect(company_rows.first[:folio_count]).to eq(2)
    end

    it "orders guests before companies before unassigned" do
      create(:booking_folio, booking: booking, hotel: hotel, is_primary: true, payer_type: "guest")
      create(:booking_folio, :secondary, booking: booking, hotel: hotel,
                             hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel))
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, name: "Legacy Folio")
        .update_column(:hotel_corporate_account_id, nil)

      rows = described_class.new(booking.reload, hotel: hotel).financial_party_rows

      expect(rows.map { |row| row[:kind] }).to eq([ "Guest", "Company", "—" ])
    end

    it "returns no rows when the booking has no folios" do
      expect(described_class.new(booking.reload, hotel: hotel).billing_party_rows).to be_empty
    end
  end

  describe "default entity selection" do
    it "selects the primary guest when no booking_guest_id is provided" do
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Primary"), is_primary: true)
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Additional"), is_primary: false)

      tab_presenter = described_class.new(booking.reload, params: { tab: "guest_details" }, hotel: hotel)

      expect(tab_presenter.selected_booking_guest&.primary?).to be(true)
    end

    it "selects a folio when no folio_id is provided" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      tab_presenter = described_class.new(booking.reload, params: { tab: "folio_operations" }, hotel: hotel)

      expect(tab_presenter.selected_folio).to eq(folio)
    end

    it "selects the first group child and its primary folio and guest without entity IDs" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      create(:booking_folio, :secondary, booking: first_child, hotel: hotel, folio_sequence: 1)
      primary_folio = create(:booking_folio, booking: first_child, hotel: hotel, is_primary: true, folio_sequence: 3)
      create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: false)
      primary_guest = create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: true)

      folio_presenter = described_class.new(booking.reload, params: { tab: "folio_operations" }, hotel: hotel)
      guest_presenter = described_class.new(booking.reload, params: { tab: "guest_details" }, hotel: hotel)

      expect(folio_presenter).to have_attributes(selected_child_booking: first_child, selected_folio: primary_folio)
      expect(guest_presenter).to have_attributes(selected_child_booking: first_child, selected_booking_guest: primary_guest)
    end

    it "resolves explicit group entities to their owning child and ignores foreign IDs" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      sibling_folio = create(:booking_folio, booking: sibling, hotel: hotel)
      sibling_guest = create(:booking_guest, booking: sibling, guest: create(:guest), is_primary: true)
      foreign_hotel = create(:hotel)
      foreign_booking = create(:booking, hotel: foreign_hotel)
      foreign_folio = create(:booking_folio, hotel: foreign_hotel, booking: foreign_booking)

      folio_presenter = described_class.new(booking, params: { tab: "folio_operations", folio_id: sibling_folio.id }, hotel: hotel)
      guest_presenter = described_class.new(booking, params: { tab: "guest_details", booking_guest_id: sibling_guest.id }, hotel: hotel)
      foreign_presenter = described_class.new(booking, params: { tab: "folio_operations", folio_id: foreign_folio.id }, hotel: hotel)

      expect(folio_presenter).to have_attributes(selected_child_booking: sibling, selected_folio: sibling_folio)
      expect(guest_presenter).to have_attributes(selected_child_booking: sibling, selected_booking_guest: sibling_guest)
      expect(foreign_presenter.selected_child_booking).to eq(booking)
      expect(foreign_presenter.selected_folio).not_to eq(foreign_folio)
    end

    it "excludes inconsistent group children belonging to another hotel" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      foreign_hotel = create(:hotel)
      foreign_child = create(:booking, hotel: foreign_hotel)
      foreign_child.update_column(:group_booking_id, group.id)
      group.bookings.reset

      group_presenter = described_class.new(booking, params: { tab: "folio_operations" }, hotel: hotel)

      expect(group_presenter.child_bookings).to eq([ booking ])
      expect(group_presenter.child_bookings).not_to include(foreign_child)
    end
  end

  describe "left rail modes" do
    it "renders no rail for ordinary standalone tabs" do
      %w[booking_details billing_preferences security_deposits source_details room_and_rate housekeeping_requests].each do |tab|
        tab_presenter = described_class.new(booking, params: { tab: tab })

        expect(tab_presenter.left_rail_mode).to be_nil
        expect(tab_presenter.layout_mode).to eq("standard")
        expect(tab_presenter.show_left_rail?).to be(false)
      end
    end

    it "uses entity context only for folio and guest tabs" do
      folio_presenter = described_class.new(booking, params: { tab: "folio_operations" })
      guest_presenter = described_class.new(booking, params: { tab: "guest_details" })
      audit_presenter = described_class.new(booking, params: { tab: "audit_trails" })

      expect(folio_presenter).to have_attributes(left_rail_mode: "folio_tree", layout_mode: "entity", show_left_rail?: true)
      expect(guest_presenter).to have_attributes(left_rail_mode: "guest_tree", layout_mode: "entity", show_left_rail?: true)
      expect(audit_presenter).to have_attributes(left_rail_mode: nil, layout_mode: "standard", show_left_rail?: false)
    end

    it "renders no rail for ordinary grouped tabs" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      room_presenter = described_class.new(booking, params: { tab: "room_and_rate" })
      billing_presenter = described_class.new(booking, params: { tab: "billing_preferences" })
      deposits_presenter = described_class.new(booking, params: { tab: "security_deposits" })
      requests_presenter = described_class.new(booking, params: { tab: "housekeeping_requests" })

      expect(room_presenter).to have_attributes(show_left_rail?: false, layout_mode: "standard")
      expect(billing_presenter).to have_attributes(show_left_rail?: false, billing_scope: "group")
      expect(deposits_presenter).to have_attributes(show_left_rail?: false, layout_mode: "standard")
      expect(requests_presenter).to have_attributes(show_left_rail?: false, layout_mode: "standard")
    end

    it "never reports a rail without a rail partial to render" do
      enable_audit_feature

      (described_class::TABS.map(&:key) + described_class::LEGACY_TABS.map(&:key)).each do |tab|
        tab_presenter = described_class.new(booking, params: { tab: tab })

        expect(tab_presenter.show_left_rail?).to eq(tab_presenter.left_rail_mode.present?)
      end
    end

    it "uses one rail partial for standalone and grouped bookings" do
      standalone_folios = described_class.new(booking, params: { tab: "folio_operations" }).left_rail_mode
      standalone_guests = described_class.new(booking, params: { tab: "guest_details" }).left_rail_mode

      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      expect(described_class.new(booking, params: { tab: "folio_operations" }).left_rail_mode).to eq(standalone_folios)
      expect(described_class.new(booking, params: { tab: "guest_details" }).left_rail_mode).to eq(standalone_guests)
      expect([ standalone_folios, standalone_guests ]).to eq(%w[folio_tree guest_tree])
    end

    it "registers the adjusted tab order and Requests label" do
      enable_audit_feature
      expect(presenter.tabs.map { |tab| [ tab.key, tab.label ] }).to eq([
        [ "booking_details", "Overview" ],
        [ "folio_operations", "Folios" ],
        [ "security_deposits", "Deposits" ],
        [ "billing_preferences", "Billing" ],
        [ "guest_details", "Guests" ],
        [ "room_and_rate", "Room & Rate" ],
        [ "housekeeping_requests", "Requests" ],
        [ "audit_trails", "Audit Trail" ]
      ])
    end

    it "supports Source Details as a legacy destination without navigating to it" do
      legacy_presenter = described_class.new(booking, params: { tab: "source_details" })

      expect(legacy_presenter.active_tab).to eq("source_details")
      expect(legacy_presenter.active_tab_label).to eq("Source Details")
      expect(legacy_presenter.navigation_active_tab).to be_nil
      expect(legacy_presenter.tabs.map(&:key)).not_to include("source_details")
    end

    it "separates warning alerts from true editor drawers" do
      alert_presenter = described_class.new(booking, params: { tab: "room_and_rate", alert_action: "change_rate" })
      invalid_alert_presenter = described_class.new(booking, params: { tab: "room_and_rate", alert_action: "change_room" })
      removed_drawer_presenter = described_class.new(booking, params: { tab: "billing_preferences", drawer: "billing" })
      drawer_presenter = described_class.new(booking, params: { tab: "folio_operations", drawer: "deposit" })
      standard_drawer_presenter = described_class.new(booking, params: { tab: "security_deposits", drawer: "deposit" })

      expect(alert_presenter).to have_attributes(alert_action: "change_rate", alert_open?: true, layout_mode: "standard", show_right_drawer?: false)
      expect(invalid_alert_presenter).to have_attributes(alert_action: nil, alert_open?: false)
      expect(removed_drawer_presenter).to have_attributes(layout_mode: "standard", show_right_drawer?: false)
      expect(drawer_presenter).to have_attributes(layout_mode: "entity", show_right_drawer?: true)
      expect(standard_drawer_presenter).to have_attributes(layout_mode: "standard", show_left_rail?: false, show_right_drawer?: true)
    end
  end

  describe "context tree groups" do
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

      expect(tab_presenter.folio_tree_groups.map(&:label)).to include("Room 101", "Room 102")
      expect(tab_presenter.folio_tree_groups.map(&:description)).to include(
        booking.booking_rooms.first.room_type.name,
        sibling.booking_rooms.first.room_type.name
      )
      expect(tab_presenter.folio_tree_groups.flat_map(&:rows).map(&:label)).to include("Guest Folio", "Corporate Folio")
      expect(tab_presenter.folio_tree_groups.flat_map(&:rows).map(&:description)).to include(
        "Open · #{booking.booking_folios.first.payer_display_label} · MYR 0.00",
        "Open · #{sibling.booking_folios.first.payer_display_label} · MYR 0.00"
      )
    end

    it "treats legacy group scope as an entity view and selects the explicit folio" do
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

      expect(group_presenter).not_to be_group_overview
      expect(group_presenter.folio_tree_groups.flat_map(&:rows).select(&:active).map(&:id)).to eq([ current_folio.id ])
    end

    it "builds grouped guest hierarchy as child bookings with guests" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Primary One"), is_primary: true)
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Primary Two"), is_primary: true)

      tab_presenter = described_class.new(booking, params: { tab: "guest_details" }, hotel: hotel)

      expect(tab_presenter.guest_tree_groups.map(&:label)).to contain_exactly(
        booking.formatted_reservation_number,
        sibling.formatted_reservation_number
      )
      expect(tab_presenter.guest_tree_groups.map(&:description)).to all(be_nil)
      expect(tab_presenter.guest_tree_groups.flat_map(&:rows).map(&:label)).to contain_exactly("Primary One", "Primary Two")
    end

    it "orders standalone guest rows under a room and room-type heading" do
      room = create(:booking_room, booking: booking, room_number: "208")
      additional = create(:booking_guest, booking: booking, guest: create(:guest, name: "Additional Guest"), is_primary: false)
      primary = create(:booking_guest, booking: booking, guest: create(:guest, name: "Primary Guest"), is_primary: true)
      tab_presenter = described_class.new(booking, params: { tab: "guest_details", booking_guest_id: additional.id }, hotel: hotel)

      expect(tab_presenter.guest_tree_groups.size).to eq(1)
      expect(tab_presenter.guest_tree_groups.first).to have_attributes(
        label: "Room 208",
        description: room.room_type.name
      )
      expect(tab_presenter.guest_tree_groups.flat_map(&:rows).map(&:id)).to eq([ primary.id, additional.id ])
      expect(tab_presenter.guest_tree_groups.flat_map(&:rows).select(&:active).map(&:id)).to eq([ additional.id ])
    end

    it "uses a failed guest form for submitted values and errors" do
      booking_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Original Guest"), is_primary: true)
      guest_form = booking_guest.guest.dup
      guest_form.assign_attributes(name: "", email: "submitted@example.com")
      guest_form.valid?

      tab_presenter = described_class.new(
        booking,
        params: { tab: "guest_details", booking_guest_id: booking_guest.id },
        hotel: hotel,
        guest_form: guest_form
      )

      expect(tab_presenter.selected_guest).to eq(guest_form)
      expect(tab_presenter.guest_details_snapshots).to include(name: "", email: "submitted@example.com")
      expect(tab_presenter.guest_display[:name]).to eq("Guest details")
      expect(tab_presenter.selected_guest.errors[:name]).to be_present
    end

    it "falls back to booking numbers when children have no room to lead with" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      tab_presenter = described_class.new(booking, params: { tab: "folio_operations" }, hotel: hotel)
      groups = tab_presenter.folio_tree_groups

      expect(groups.map(&:label)).to eq(
        tab_presenter.child_bookings.map(&:formatted_reservation_number)
      )
      expect(groups.map(&:description)).to all(be_nil)
    end

    it "leads with the room number and qualifies it with the room type" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      room = create(:booking_room, booking: booking, room_number: "103")
      create(:booking_room, booking: sibling, room_number: "107")

      groups = described_class.new(booking, params: { tab: "guest_details" }, hotel: hotel).guest_tree_groups

      expect(groups.map(&:label)).to eq(%w[Room\ 103 Room\ 107])
      expect(groups.first.description).to eq(room.room_type.name)
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
      enable_audit_feature
      expect(described_class.new(booking, params: { tab: "audit_trails" })).to have_attributes(
        show_left_rail?: false,
        left_rail_mode: nil
      )
    end

    it "marks default folio active only for folio operations" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      folio_presenter = described_class.new(booking, params: { tab: "folio_operations" })
      room_presenter = described_class.new(booking, params: { tab: "booking_details" })

      folio_rows = folio_presenter.folio_tree_groups.flat_map(&:rows)
      room_rows = room_presenter.folio_tree_groups.flat_map(&:rows)

      expect(folio_rows.find { |row| row.id == folio.id }).to have_attributes(active: true)
      expect(folio_rows.find { |row| row.id == folio.id }.href).not_to include("folio_tab")
      expect(room_rows.find { |row| row.id == folio.id }).to have_attributes(active: false)
    end
  end
end
