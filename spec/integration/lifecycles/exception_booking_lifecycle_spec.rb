# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Exception Booking Lifecycles", type: :integration do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:business_date) { hotel.business_date_for }

  before do
    # Give user permissions
    admin_role = create(:role, name: "Admin", slug: "admin", account: hotel.account)
    lock_permission = create(:permission, name: "Override Date Lock", slug: "override_financial_date_lock")
    admin_role.role_permissions.create!(permission: lock_permission)
    user.user_hotel_accesses.create!(hotel: hotel, role: admin_role)
  end

  describe "1. No Show and Reinstatement Lifecycle" do
    it "marks a guest no-show, applies penalty, then reinstates them the next day with catch-up charges" do
      # Guest booked for 2 nights at 100/night
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 2.days, total_amount: 200.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0, quantity: 1, room_number: "101")

      # Assign inventory explicitly (simulating pre-assigned room)
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

      # 1. Night Audit Day 1 Runs (Guest never arrived)
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "running", trigger_mode: "manual")
      biz_date_record = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: business_date)
      biz_date_record.start_audit!
      Bookings::ProcessNoShows.call(night_audit: audit_day_1, user: user)
      audit_day_1.update!(status: "completed")
      biz_date_record.complete_audit!

      booking.reload
      expect(booking.status).to eq("no_show")

      folio = booking.booking_folio
      expect(folio.folio_transactions.charge.sum(:amount)).to eq(100.0) # 1 night penalty posted

      # 2. Next Day: Guest arrives at 10 AM, claiming flight delay. Reinstatement!
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)

      # Reinstate booking
      booking.transition_status_to!("checked_in", event: "reinstate")

      # Process catch up charges (Reverse penalty, post Day 1 as an actual room charge)
      Folios::ProcessCatchUpCharges.call(booking: booking, user: user, is_reinstate: true)

      # Verify: The penalty should be reversed (-100 adjustment), and an actual charge (+100) posted.
      expect(folio.folio_transactions.adjustment.sum(:amount)).to eq(-100.0)
      # Penalty(100) + Reinstated Room Charge(100) = 200 total charge amount.
      expect(folio.folio_transactions.charge.sum(:amount)).to eq(200.0)

      # Total balance should still be 100.0
      expect(folio.outstanding_balance).to eq(100.0)
    end
  end

  describe "2. Early Departure Lifecycle" do
    it "truncates a long stay and settles the folio correctly" do
      # Guest booked for 5 nights
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 5.days, total_amount: 500.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 500.0, quantity: 1)

      booking.transition_status_to!("checked_in", event: "check_in")
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      # Night 1
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "completed", trigger_mode: "manual")
      biz_date_record = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: business_date)
      biz_date_record.start_audit!
      Folios::PostNightlyCharges.call(night_audit: audit_day_1, user: user)
      biz_date_record.complete_audit!

      # Night 2
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)
      audit_day_2 = hotel.night_audits.create!(business_date: business_date + 1.day, status: "completed", trigger_mode: "manual")
      biz_date_record_2 = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: business_date + 1.day)
      biz_date_record_2.start_audit!
      Folios::PostNightlyCharges.call(night_audit: audit_day_2, user: user)
      biz_date_record_2.complete_audit!

      # Day 3 morning: Guest needs to leave early.
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 2.days)

      # Front desk updates checkout date
      booking.update!(check_out: business_date + 2.days)

      # Guest pays for the 2 nights they stayed (200.0)
      Folios::InsertTransaction.new(
        booking_folio: folio, amount: 200.0, transaction_type: :payment, category: "cash", user: user,
        description: "Payment for truncated stay", posting_date: business_date + 2.days
      ).call

      # Checkout should succeed because all expected dates (Day 1, Day 2) have charges!
      result = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result.success?).to be(true)
      expect(folio.reload.status).to eq("closed")
    end
  end

  describe "3. Unpaid Walk-out (Write-Off) Lifecycle" do
    it "blocks checkout for unpaid balance, forcing staff to write-off before closure" do
      # 1 Night stay
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 1.day, total_amount: 100.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 100.0, quantity: 1)

      booking.transition_status_to!("checked_in", event: "check_in")
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      # Night Audit
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "completed", trigger_mode: "manual")
      biz_date_record = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: business_date)
      biz_date_record.start_audit!
      Folios::PostNightlyCharges.call(night_audit: audit_day_1, user: user)
      biz_date_record.complete_audit!

      # Next morning
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)

      # Guest walked out without paying.
      # Staff attempts to just close the folio
      result = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result.success?).to be(false)
      expect(result.error).to include("Cannot check out with outstanding balance")

      # Staff posts a Write-Off adjustment
      Folios::InsertTransaction.new(
        booking_folio: folio, amount: -100.0, transaction_type: :adjustment, category: "write_off", user: user,
        description: "Unpaid walk-out, writing off balance", posting_date: business_date + 1.day
      ).call

      # Now checkout succeeds
      result2 = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result2.success?).to be(true)
      expect(folio.reload.status).to eq("closed")
    end
  end

  describe "4. Reinstatement with Room/Rate Change" do
    it "reinstates a no-show guest into a different room type with a different rate" do
      # 1. Day 1: Guest booked into a Standard Room at 100/night
      check_in = business_date
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: check_in, check_out: check_in + 2.days, total_amount: 200.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0, quantity: 1)

      # 2. Night Audit Day 1: No Show
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "running", trigger_mode: "manual")
      biz_date_record = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: business_date)
      biz_date_record.start_audit!
      Bookings::ProcessNoShows.call(night_audit: audit_day_1, user: user)
      audit_day_1.update!(status: "completed")
      biz_date_record.complete_audit!

      expect(booking.reload.status).to eq("no_show")
      expect(booking.booking_folio.folio_transactions.charge.sum(:amount)).to eq(100.0) # Penalty (1 night)

      # 3. Day 2 Morning: Guest arrives. Original room type is full.
      # Staff changes booking to Deluxe Room (150/night)
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)

      deluxe_room_type = create(:room_type, hotel: hotel, name: "Deluxe")
      booking_room = booking.booking_rooms.first
      booking_room.update!(
        room_type: deluxe_room_type,
        subtotal: 300.0, # 150 * 2
        nightly_rate_snapshot: {
          business_date.iso8601 => { "price" => 150.0 },
          (business_date + 1.day).iso8601 => { "price" => 150.0 }
        }
      )

      # 4. Reinstate
      booking.transition_status_to!("checked_in", event: "reinstate")
      Folios::ProcessCatchUpCharges.call(booking: booking, user: user, is_reinstate: true)

      # Verify:
      # - Original 100.0 penalty reversed (adjustment of -100)
      # - New Day 1 charge posted at 150.0 (catch-up)
      folio = booking.booking_folio
      expect(folio.folio_transactions.adjustment.where(category: "correction").sum(:amount)).to eq(-100.0)
      # Catch-up charge is 150.0. Penalty is 100.0.
      expect(folio.folio_transactions.charge.where(category: "accommodation").sum(:amount)).to eq(250.0)

      # Net debt after Day 1 is now 150.0
      expect(folio.outstanding_balance).to eq(150.0)
    end
  end

  describe "5. Overpayment & Refund at Checkout" do
    it "blocks checkout for credit balance and requires a refund" do
      # 1. Guest pays 500 advance deposit for a long stay
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 5.days, total_amount: 500.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 500.0, quantity: 1)

      payment = create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 50_000, captured_at: Time.current)
      Folios::RecordPaymentFromGateway.call(payment)

      booking.transition_status_to!("checked_in", event: "check_in")
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      # 2. Stay 2 nights
      [ 0, 1 ].each do |offset|
        date = business_date + offset.days
        allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(date)
        audit = hotel.night_audits.create!(business_date: date, status: "completed", trigger_mode: "manual")
        biz_date_record = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: date)
        biz_date_record.start_audit!
        Folios::PostNightlyCharges.call(night_audit: audit, user: user)
        biz_date_record.complete_audit!
      end

      # 3. Guest leaves early on Day 3 morning (Total charges = 200)
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 2.days)
      booking.update!(check_out: business_date + 2.days)

      # Balance = 200 charges - 500 payment = -300 credit
      expect(folio.outstanding_balance).to eq(-300.0)

      # 4. Attempt checkout -> Blocked
      result = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result.success?).to be(false)
      expect(result.error).to include("credit balance")

      # 5. Process Refund
      refund_req = create(:refund_request, booking: booking, refund_amount: 300.0, status: "pending")
      # Admin completes refund
      Folios::RecordRefund.call(refund_request: refund_req, user: user, posting_date: business_date + 2.days)

      # 6. Checkout now succeeds
      expect(folio.outstanding_balance).to eq(0.0)
      result2 = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result2.success?).to be(true)
    end
  end

  describe "6. Mid-Audit Crash & Recovery (Idempotency)" do
    it "ensures night audit can be safely resumed without double-charging" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: business_date, check_out: business_date + 2.days, total_amount: 200.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0, quantity: 1)
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      audit = hotel.night_audits.create!(business_date: business_date, status: "running", trigger_mode: "manual")
      biz_date_record = HotelBusinessDate.for_hotel_date!(hotel: hotel, date: business_date)
      biz_date_record.start_audit!

      # 1. First run of posting charges
      Folios::PostNightlyCharges.call(night_audit: audit, user: user)
      expect(folio.folio_transactions.charge.count).to eq(1)
      expect(folio.outstanding_balance).to eq(100.0)

      # 2. Simulate CRASH (audit status stays running, or moves to failed, but we just run the service again)
      # 3. Second run of posting charges (Resume)
      expect {
        Folios::PostNightlyCharges.call(night_audit: audit, user: user)
      }.not_to change { folio.folio_transactions.count }

      expect(folio.outstanding_balance).to eq(100.0)

      # 4. Finalize audit
      biz_date_record.complete_audit!
      expect(biz_date_record.status).to eq("closed")
    end
  end
end
