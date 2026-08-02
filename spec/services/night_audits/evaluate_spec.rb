require 'rails_helper'

RSpec.describe NightAudits::Evaluate do
  let(:hotel) { create(:hotel) }
  let(:business_date) { Date.current - 1.day }
  let(:service) { described_class.new(hotel: hotel, business_date: business_date) }

  describe '#call' do
    it 'returns a hash with blocked_details, exceptions, and summary' do
      result = service.call
      expect(result.keys).to eq(%i[blocked_details exceptions summary])
      expect(result[:blocked_details].keys).to all(be_a(String))
      expect(result[:exceptions].keys).to all(be_a(String))
      expect(result[:summary].keys).to all(be_a(String))
    end

    it 'rejects unsupported phases before evaluating any rules' do
      expect do
        described_class.new(hotel: hotel, business_date: business_date, phase: :during_close).call
      end.to raise_error(ArgumentError, /during_close/)
    end

    it 'rejects a nil phase with ArgumentError' do
      expect do
        described_class.new(hotel: hotel, business_date: business_date, phase: nil).call
      end.to raise_error(ArgumentError, /nil/)
    end

    it 'counts payment statuses only for bookings financially relevant to the business date' do
      create(:booking,
        hotel: hotel,
        status: 'checked_in',
        payment_status: 'captured',
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking,
        hotel: hotel,
        status: 'completed',
        payment_status: 'failed',
        check_in: business_date - 10.days,
        check_out: business_date - 9.days,
        checked_out_at: business_date - 9.days)
      create(:booking,
        hotel: hotel,
        status: 'confirmed',
        payment_status: 'authorized',
        check_in: business_date + 5.days,
        check_out: business_date + 6.days)

      counts = service.call.dig(:summary, "payment_status_counts")

      expect(counts).to eq("captured" => 1)
    end

    it 'identifies stale checked-in due outs as blockers' do
      create(:booking, status: 'checked_in', hotel: hotel, check_out: business_date)
      result = service.call
      expect(result[:blocked_details]["due_out_not_checked_out"]).not_to be_empty
    end

    it 'keeps due-out detections as staff-action blockers' do
      booking = create(:booking, status: 'due_out_detected', hotel: hotel, check_in: business_date - 1.day, check_out: business_date)
      create(:booking_folio, booking: booking)

      result = service.call

      expect(result[:blocked_details]["due_out_not_checked_out"].sole["booking_id"]).to eq(booking.id)
      expect(result[:exceptions]).not_to have_key("due_out_detected")
    end

    it 'keeps no-show detections as staff-action blockers' do
      booking = create(:booking, status: 'no_show_detected', hotel: hotel, check_in: business_date, check_out: business_date + 1.day, no_show_detected_business_date: business_date)

      result = service.call

      expect(result[:blocked_details]["missed_arrival_not_resolved"].sole["booking_id"]).to eq(booking.id)
      expect(result[:exceptions]).not_to have_key("no_show_detected")
    end

    it 'does not call a same-day confirmed arrival missed before the business date is closable' do
      hotel.update!(time_zone: "Kuala Lumpur", business_starts_at: "08:00", business_ends_at: "02:00")
      zone = hotel.hotel_time_zone
      local_date = Date.new(2026, 8, 2)
      booking = create(:booking,
        hotel: hotel,
        status: "confirmed",
        check_in: zone.local(2026, 8, 2, 15, 0),
        check_out: zone.local(2026, 8, 3, 11, 0))

      with_frozen_time(zone.local(2026, 8, 2, 20, 0)) do
        result = described_class.new(hotel: hotel, business_date: local_date, phase: :pre_close).call
        expect(result[:blocked_details]["missed_arrival_not_resolved"].pluck("booking_id")).not_to include(booking.id)
      end
    end

    it 'honors a completed pre-check-in declared-arrival grace period' do
      hotel.update!(
        time_zone: "Kuala Lumpur",
        business_starts_at: "08:00",
        business_ends_at: "02:00",
        arrival_grace_period: 2.hours.to_i
      )
      zone = hotel.hotel_time_zone
      local_date = Date.new(2026, 8, 1)
      booking = create(:booking,
        hotel: hotel,
        status: "confirmed",
        check_in: zone.local(2026, 8, 1, 15, 0),
        check_out: zone.local(2026, 8, 2, 11, 0))
      create(:pre_checkin,
        booking: booking,
        status: "completed",
        completed_at: zone.local(2026, 8, 1, 12, 0),
        metadata: { "estimated_arrival_time" => "01:30" })

      with_frozen_time(zone.local(2026, 8, 2, 2, 30)) do
        within_grace = described_class.new(hotel: hotel, business_date: local_date, phase: :pre_close).call
        expect(within_grace[:blocked_details]["missed_arrival_not_resolved"]).to be_empty
      end

      with_frozen_time(zone.local(2026, 8, 2, 3, 31)) do
        expired = described_class.new(hotel: hotel, business_date: local_date, phase: :pre_close).call
        expect(expired[:blocked_details]["missed_arrival_not_resolved"].sole["booking_id"]).to eq(booking.id)
      end
    end

    it 'treats checkout_required bookings as due-out blockers' do
      booking = create(:booking, status: 'checkout_required', hotel: hotel, check_out: business_date)

      result = service.call

      expect(result[:blocked_details]["due_out_not_checked_out"].sole["booking_id"]).to eq(booking.id)
    end

    it 'includes missing folios but omits missing nightly charges during pre-close evaluation' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking_room, booking: booking, subtotal: 120.0)

      result = described_class.new(hotel: hotel, business_date: business_date, phase: :pre_close).call

      expect(result[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
      expect(result[:blocked_details]).not_to have_key("missing_nightly_charges")
    end

    it 'includes posting-generated blockers during post-close evaluation' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      create(:booking_room, booking: booking, subtotal: 120.0)

      result = described_class.new(hotel: hotel, business_date: business_date, phase: :post_close).call

      expect(result[:blocked_details]["missing_folio"].first["booking_id"]).to eq(booking.id)
    end

    it 'keeps a missing folio as a blocker for a chargeable checked-in booking' do
      booking = create(:booking,
        status: 'checked_in',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)

      result = service.call

      expect(result[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
      expect(result[:exceptions]).not_to have_key("missing_folio")
    end

    it 'keeps a missing folio as an accounting blocker after due-out detection' do
      booking = create(:booking,
        status: 'due_out_detected',
        hotel: hotel,
        check_in: business_date - 1.day,
        check_out: business_date)

      result = service.call

      expect(result[:blocked_details]["missing_folio"].sole["booking_id"]).to eq(booking.id)
      expect(result[:blocked_details]["due_out_not_checked_out"].sole["booking_id"]).to eq(booking.id)
    end

    it 'does not require a folio for proven non-chargeable bookings' do
      cancelled = create(:booking,
        status: 'cancelled',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day)
      no_show = create(:booking,
        status: 'no_show',
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day)

      result = service.call

      missing_folio_ids = result[:blocked_details]["missing_folio"].pluck("booking_id")
      expect(missing_folio_ids).not_to include(cancelled.id, no_show.id)
    end

    it 'identifies large balance exceptions' do
      booking = create(:booking, status: 'checked_in', hotel: hotel)
      folio = create(:booking_folio, booking: booking)
      create(:folio_transaction, :charge, booking_folio: folio, amount: 2000, category: "other")

      result = service.call
      expect(result[:exceptions]["folio_balance_exceptions"]).not_to be_empty
      expect(result[:exceptions]["folio_balance_exceptions"].first["reason"]).to eq("Large outstanding balance")
    end

    it "accepts exact nightly lines distributed across their resolved folios" do
      booking = create(:booking,
        status: "checked_in",
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      room = create(:booking_room, booking: booking, subtotal: 100.0)
      guest_folio = create(:booking_folio, hotel: hotel, booking: booking)
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
      key = Folios::Charges::ChargePostingKeys.nightly_charge_key(booking: booking, date: business_date, charge_kind: "accommodation", identity: room.id)
      create(:folio_transaction,
        booking_folio: company_folio,
        transaction_type: "charge",
        category: "accommodation",
        transaction_code: room_code,
        amount: 100.0,
        metadata: { nightly_charge_key: key, stay_date: business_date.iso8601, posting_source: "night_audit" })

      result = service.call

      expect(result[:blocked_details]["missing_nightly_charges"]).to be_empty
      expect(guest_folio.folio_transactions).to be_empty
    end

    it "reports per-line metadata when a nightly line is on the wrong folio" do
      booking = create(:booking,
        status: "checked_in",
        hotel: hotel,
        check_in: business_date,
        check_out: business_date + 1.day,
        checked_in_at: business_date.beginning_of_day)
      room = create(:booking_room, booking: booking, subtotal: 100.0)
      guest_folio = create(:booking_folio, hotel: hotel, booking: booking)
      company_folio = create(:booking_folio, :secondary, hotel: hotel, booking: booking)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: room_code, target_folio: company_folio)
      key = Folios::Charges::ChargePostingKeys.nightly_charge_key(booking: booking, date: business_date, charge_kind: "accommodation", identity: room.id)
      transaction = create(:folio_transaction,
        booking_folio: guest_folio,
        transaction_type: "charge",
        category: "accommodation",
        transaction_code: room_code,
        amount: 100.0,
        metadata: { nightly_charge_key: key, stay_date: business_date.iso8601, posting_source: "night_audit" })

      issue = service.call[:blocked_details]["missing_nightly_charges"].sole["line_issues"].sole

      expect(issue["issue_types"]).to include("misrouted")
      expect(issue["expected_folio_id"]).to eq(company_folio.id)
      expect(issue.dig("actual_transactions", 0, "folio_transaction_id")).to eq(transaction.id)
    end

    it "blocks a missing final-night charge using the hotel's local dates" do
      hotel.update!(time_zone: "Kuala Lumpur")
      zone = hotel.hotel_time_zone
      local_business_date = Date.new(2026, 7, 25)
      booking = create(:booking,
        status: "checked_in",
        hotel: hotel,
        check_in: zone.local(2026, 7, 23, 0, 0),
        check_out: zone.local(2026, 7, 26, 0, 0),
        checked_in_at: zone.local(2026, 7, 23, 0, 0))
      create(:booking_room,
        booking: booking,
        subtotal: 30.0,
        nightly_rate_snapshot: { local_business_date.iso8601 => { "price" => "10.00" } })
      create(:booking_folio, booking: booking, hotel: hotel)

      result = described_class.new(hotel: hotel, business_date: local_business_date, phase: :post_close).call

      blocker = result[:blocked_details]["missing_nightly_charges"].sole
      expect(blocker["booking_id"]).to eq(booking.id)
      expect(blocker["line_issues"].sole["stay_date"]).to eq("2026-07-25")
      expect(blocker["line_issues"].sole["issue_types"]).to include("missing")
    end

    it "evaluates checkout balances on the hotel's local departure date" do
      hotel.update!(time_zone: "Kuala Lumpur")
      zone = hotel.hotel_time_zone
      local_business_date = Date.new(2026, 7, 25)
      booking = create(:booking,
        status: "checked_in",
        hotel: hotel,
        check_in: zone.local(2026, 7, 24, 0, 0),
        check_out: zone.local(2026, 7, 25, 0, 0),
        checked_in_at: zone.local(2026, 7, 24, 0, 0))
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, :charge, booking_folio: folio, amount: 50, category: "other")

      result = described_class.new(hotel: hotel, business_date: local_business_date, phase: :pre_close).call

      expect(result[:blocked_details]["outstanding_folio_balance"].sole["booking_id"]).to eq(booking.id)
    end
  end
end
