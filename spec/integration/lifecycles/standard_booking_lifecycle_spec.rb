# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Standard Booking Lifecycles", type: :integration do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:business_date) { hotel.current_business_date }

  before do
    # Give user permissions
    admin_role = create(:role, name: "Admin", account: hotel.account)
    user.user_hotel_accesses.create!(hotel: hotel, role: admin_role)
  end

  describe "1. Fully Prepaid (Booking Payment) Lifecycle" do
    it "flows from check-in to night audit to checkout seamlessly" do
      # Guest booked for 2 nights at 100/night = 200 total
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 2.days, total_amount: 200.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0)

      # 1. Booking Payment (Simulate gateway payment sync)
      payment = create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 20_000, captured_at: Time.current)
      Folios::RecordPaymentFromGateway.call(payment)

      # 2. Check-in
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      # Ensure booking payment synced into folio
      expect(folio.folio_transactions.payment.sum(:amount)).to eq(200.0)
      expect(folio.outstanding_balance).to eq(-200.0) # Credit balance

      # 3. Night Audit Day 1
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "pending", trigger_mode: "manual")
      biz_date_record = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_1, user: user)
      audit_day_1.update!(status: "completed")
      close_and_open_next_business_date(hotel)

      expect(folio.outstanding_balance).to eq(-100.0)

      # 4. Night Audit Day 2
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)
      audit_day_2 = hotel.night_audits.create!(business_date: business_date + 1.day, status: "pending", trigger_mode: "manual")
      biz_date_record_2 = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_2, user: user)
      audit_day_2.update!(status: "completed")
      close_and_open_next_business_date(hotel)

      # Balance is now exactly 0
      expect(folio.outstanding_balance).to eq(0.0)

      # 5. Checkout on Day 3
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 2.days)
      result = Folios::CloseForCheckout.call(booking: booking, user: user)

      expect(result.success?).to be(true)
      expect(folio.reload.status).to eq("closed")
    end
  end

  describe "2. Pay at Checkout & Report Reconciliation" do
    it "accrues debt via night audit, settles at checkout, and reconciles reports" do
      # 1. Create a 2-night booking (No upfront payment)
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 2.days, total_amount: 200.0)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 200.0)

      # Initially, reports should show 0 revenue because nothing is posted yet
      summary = Booking.analytics_summary(Date.current, Date.current, base_scope: hotel.bookings)
      expect(summary[:total_revenue]).to eq(0)

      # 2. Check-in
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)
      expect(folio.outstanding_balance).to eq(0.0)

      # 3. Run Night Audit for Day 1
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "pending", trigger_mode: "manual")
      biz_date_record = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_1, user: user)
      audit_day_1.update!(status: "completed")
      close_and_open_next_business_date(hotel)

      # Verify 1 charge posted
      expect(folio.folio_transactions.charge.count).to eq(1)
      expect(folio.outstanding_balance).to eq(100.0)

      # Verify Report now shows ledger data (100.00)
      summary = Booking.analytics_summary(Date.current, Date.current, base_scope: hotel.bookings)
      expect(summary[:total_revenue]).to eq(100.0)

      # 4. Night Audit Day 2
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)
      audit_day_2 = hotel.night_audits.create!(business_date: business_date + 1.day, status: "pending", trigger_mode: "manual")
      biz_date_record_2 = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_2, user: user)
      audit_day_2.update!(status: "completed")
      close_and_open_next_business_date(hotel)

      expect(folio.outstanding_balance).to eq(200.0)

      # 5. Attempt Checkout EARLY (Day 3 morning)
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 2.days)
      result = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result.success?).to be(false)
      expect(result.error).to include("Cannot check out with outstanding balance")

      # 6. Settle balance (Cash)
      Folios::InsertTransaction.new(
        booking_folio: folio, amount: 200.0, transaction_type: :payment, category: "cash", user: user,
        description: "Cash settlement", posting_date: business_date + 2.days
      ).call

      # Now checkout should succeed
      result2 = Folios::CloseForCheckout.call(booking: booking, user: user)
      expect(result2.success?).to be(true)
      expect(folio.reload.status).to eq("closed")

      # 7. Final Report Check (200.00 total gross)
      summary = Booking.analytics_summary(Date.current, Date.current, base_scope: hotel.bookings)
      expect(summary[:total_revenue]).to eq(200.0)
    end
  end

  describe "3. Mid-Stay Rate Change Lifecycle" do
    it "uses the nightly rate snapshot for subsequent night audits without altering past nights" do
      # 3 nights.
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 3.days, total_amount: 300.0)
      booking_room = create(:booking_room, booking: booking, room_type: room_type, subtotal: 300.0, nightly_rate_snapshot: {
        business_date.iso8601 => { "price" => 100.0 },
        (business_date + 1.day).iso8601 => { "price" => 100.0 },
        (business_date + 2.days).iso8601 => { "price" => 100.0 }
      })

      booking.transition_status_to!("checked_in", event: "check_in")
      folio = Folios::InitializeForBooking.call(booking: booking, user: user)

      # Night 1 posts at $100
      audit_day_1 = hotel.night_audits.create!(business_date: business_date, status: "completed", trigger_mode: "manual")
      biz_date_record = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_1, user: user)
      close_and_open_next_business_date(hotel)

      # Next morning, guest decides to upgrade room or rate changes to $150 for remaining 2 nights.
      booking_room.update!(nightly_rate_snapshot: {
        business_date.iso8601 => { "price" => 100.0 },
        (business_date + 1.day).iso8601 => { "price" => 150.0 },
        (business_date + 2.days).iso8601 => { "price" => 150.0 }
      })

      # Night 2 posts at $150
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 1.day)
      audit_day_2 = hotel.night_audits.create!(business_date: business_date + 1.day, status: "completed", trigger_mode: "manual")
      biz_date_record_2 = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_2, user: user)
      close_and_open_next_business_date(hotel)

      # Night 3 posts at $150
      allow_any_instance_of(Hotel).to receive(:business_date_for).and_return(business_date + 2.days)
      audit_day_3 = hotel.night_audits.create!(business_date: business_date + 2.days, status: "completed", trigger_mode: "manual")
      biz_date_record_3 = hotel.current_business_date_record
      start_business_date_audit(hotel)
      Folios::PostNightlyCharges.call(night_audit: audit_day_3, user: user)
      close_and_open_next_business_date(hotel)

      # Total charges should be 100 + 150 + 150 = 400
      expect(folio.folio_transactions.charge.sum(:amount)).to eq(400.0)
    end
  end
end
