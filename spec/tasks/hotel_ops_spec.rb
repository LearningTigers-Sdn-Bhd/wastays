# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "hotel_ops rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  describe "hotel_ops:clean_state" do
    let(:task) { Rake::Task["hotel_ops:clean_state"] }
    let(:hotel) { create(:hotel, name: "Aurora Crown Resort Langkawi") }
    let(:other_hotel) { create(:hotel, name: "Other Hotel") }

    before do
      task.reenable
      allow_any_instance_of(Object).to receive(:sleep)
    end

    it "deletes night audit history only for the selected hotel and does not create bookings" do
      create(:room_type, hotel: hotel)
      create(:room_type, hotel: other_hotel)

      night_audit = create(:night_audit, hotel: hotel)
      other_night_audit = create(:night_audit, hotel: other_hotel)

      NightAuditLog.create!(
        night_audit: night_audit,
        hotel: hotel,
        action_type: "completed",
        message: "Completed"
      )
      create(:night_audit_financial_summary, night_audit: night_audit)

      other_log = NightAuditLog.create!(
        night_audit: other_night_audit,
        hotel: other_hotel,
        action_type: "completed",
        message: "Completed"
      )
      other_summary = create(:night_audit_financial_summary, night_audit: other_night_audit)

      expect do
        task.invoke(hotel.name)
      end.to change { hotel.night_audits.count }.from(1).to(0)

      expect(NightAudit.exists?(night_audit.id)).to be(false)
      expect(NightAuditLog.where(night_audit_id: night_audit.id)).to be_empty
      expect(NightAuditFinancialSummary.where(night_audit_id: night_audit.id)).to be_empty

      expect(NightAudit.exists?(other_night_audit.id)).to be(true)
      expect(NightAuditLog.exists?(other_log.id)).to be(true)
      expect(NightAuditFinancialSummary.exists?(other_summary.id)).to be(true)

      expect(hotel.bookings.count).to eq(0)
    end
  end

  describe "hotel_ops:realtime_state" do
    let(:task) { Rake::Task["hotel_ops:realtime_state"] }
    let(:hotel) { create(:hotel, name: "Aurora Crown Resort Langkawi") }

    before do
      task.reenable
      allow_any_instance_of(Object).to receive(:sleep)
    end

    it "prefills 25 realistic bookings for Malaysian and foreign guests with correct folios and statuses" do
      # Set up room types with room numbers for the hotel to support cycling assignment
      create(:room_type, hotel: hotel, name: "Garden Prestige Suite", base_price: 740.0, room_numbers: [ "101", "102", "103", "104", "105", "106", "107", "108" ], quantity: 8)
      create(:room_type, hotel: hotel, name: "Skyline Queen Deluxe", base_price: 560.0, room_numbers: [ "201", "202", "203", "204", "205", "206", "207", "208", "209", "210" ], quantity: 10)

      # Create a superadmin user on the hotel's account — this becomes hotel.account.users.first
      # (the acting_user resolved by the rake task). Superadmin bypasses all PostingGuard
      # permission checks, including override_financial_date_lock.
      superadmin = create(:user, role: "superadmin", account: hotel.account)
      superadmin.user_hotel_accesses.create!(hotel: hotel, role: create(:role, name: "Admin", slug: "admin", account: hotel.account))

      # Stub environments and validation methods to allow past night audits to process in test environment
      allow(Rails.env).to receive(:development?).and_return(true)
      allow_any_instance_of(Hotel).to receive(:can_audit_date?).and_return(true)

      # Run the rake task
      task.invoke(hotel.name)

      # 1. Verify counts
      expect(hotel.bookings.count).to eq(25)
      expect(Guest.count).to eq(25)

      # 2. Verify country and document distribution
      countries = [ "Malaysia", "Japan", "South Korea", "Hong Kong", "Indonesia" ]
      countries.each do |country|
        guests_in_country = Guest.where(country: country)
        expect(guests_in_country.count).to eq(5)

        if country == "Malaysia"
          guests_in_country.each do |g|
            expect(g.document_type).to eq("ic")
            expect(g.government_id).to match(/\A\d{6}-\d{2}-\d{4}\z/)
          end
        else
          guests_in_country.each do |g|
            expect(g.document_type).to eq("passport")
            expect(g.government_id).not_to be_nil
          end
        end
      end

      # 3. Verify status distribution
      expect(hotel.bookings.where(status: "no_show").count).to eq(2)
      expect(hotel.bookings.where(status: "review_due_out").count).to eq(2)

      # 4. Verify completed bookings folios are closed and balanced
      completed_bookings = hotel.bookings.where(status: "completed")
      expect(completed_bookings.count).to be > 0
      completed_bookings.each do |booking|
        folio = booking.booking_folio
        expect(folio.status).to eq("closed")
        expect(folio.outstanding_balance.to_f).to eq(0.0)

        # Verify folio transactions \u2014 booking was pre-paid at creation time.
        # At check-in, SyncExistingPayments syncs the PaymentTransaction(gateway: 'manual')
        # into the folio as category: 'booking_payment'.
        txs = folio.folio_transactions
        expect(txs.where(transaction_type: "charge", category: "accommodation").count).to be > 0
        expect(txs.where(transaction_type: "charge", category: "tax").count).to be > 0
        # Booking payment synced from the manual PaymentTransaction at check-in
        expect(txs.where(transaction_type: "payment", category: "booking_payment").count).to eq(1)
        # Confirm the underlying PaymentTransaction record (gateway: 'manual') exists on the booking
        expect(booking.payment_transactions.captured.where(gateway: "manual").count).to eq(1)
      end

      # 5. Verify no_show folios
      # Pre-paid bookings have a booking_payment FolioTransaction synced at no-show processing.
      # The folio will have: no_show_charge charge + tax charges + booking_payment payment.
      no_show_bookings = hotel.bookings.where(status: "no_show")
      no_show_bookings.each do |booking|
        folio = booking.booking_folio
        txs = folio.folio_transactions

        expect(txs.where(category: "no_show_charge").count).to eq(1)
        expect(txs.where(category: "tax").count).to be > 0
        expect(txs.where(category: "accommodation")).to be_empty
        # Booking was pre-paid so booking_payment is synced into the folio
        expect(txs.where(transaction_type: "payment", category: "booking_payment").count).to eq(1)
      end

      # 6. Verify review_due_out (late checkout) folios
      late_checkout_bookings = hotel.bookings.where(status: "review_due_out")
      late_checkout_bookings.each do |booking|
        folio = booking.booking_folio
        txs = folio.folio_transactions

        # Should have accommodation, tax, and late_checkout_charge charges
        expect(txs.where(category: "accommodation").count).to be > 0
        expect(txs.where(category: "tax").count).to be > 0
        expect(txs.where(category: "late_checkout_charge").count).to eq(1)
        # Booking was pre-paid so booking_payment is synced into the folio
        expect(txs.where(transaction_type: "payment", category: "booking_payment").count).to eq(1)
      end

      # 7. Verify the final business date is Date.current and status is open
      latest_business_date = hotel.hotel_business_dates.order(:business_date).last
      expect(latest_business_date.business_date).to eq(Date.current)
      expect(latest_business_date.status).to eq("open")

      # 8. Assert that no overlapping bookings of the same room type have the same room number
      hotel.bookings.each do |b1|
        r1 = b1.booking_rooms.first
        next unless r1&.room_number

        hotel.bookings.where.not(id: b1.id).each do |b2|
          r2 = b2.booking_rooms.first
          next unless r2 && r2.room_type_id == r1.room_type_id && r2.room_number == r1.room_number

          # If they have the same room type and same room number, they must not overlap
          overlap = b1.check_in < b2.check_out && b2.check_in < b1.check_out
          expect(overlap).to be(false), "Overlapping room assignment for room #{r1.room_number}: Booking #{b1.id} (#{b1.check_in} to #{b1.check_out}) overlaps with Booking #{b2.id} (#{b2.check_in} to #{b2.check_out})"
        end
      end
    end
  end
end
