# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::TransitionStatus do
  let(:booking) { create(:booking, status: "confirmed") }
  let(:user) { create(:user, role: "superadmin") }
  let(:timestamp) { Time.current }

  before do
    BusinessDates::ResetAuthority.call!(hotel: booking.hotel, date: timestamp.to_date)
  end

  def enable_feature_for(hotel, slug)
    plan = hotel.plan || create(:plan).tap { |record| hotel.update!(plan: record) }
    feature = Feature.find_or_create_by!(slug: slug) do |record|
      record.name = slug.humanize
      record.feature_group = FeatureGroup.first || create(:feature_group)
    end
    plan_feature = PlanFeature.find_or_initialize_by(plan: plan, feature: feature)
    plan_feature.enabled = true
    plan_feature.save!
  end

  describe "#call" do
    it "blocks staff status transitions while night audit is running" do
      booking.hotel.current_business_date_record.update!(status: "audit_running")

      result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call

      expect(result.success?).to be(false)
      expect(result.error).to eq(NightAudits::OperationalChangeGuard::ERROR_MESSAGE)
      expect(booking.reload.status).to eq("confirmed")
    end

    it "allows status transitions while night audit is blocked" do
      booking.hotel.current_business_date_record.update!(status: "audit_blocked")

      result = described_class.new(booking: booking, status: "cancelled", timestamp: timestamp).call

      expect(result.success?).to be(true)
      expect(booking.reload.status).to eq("cancelled")
    end

    context "when status is checked_in" do
      subject { described_class.new(booking: booking, status: "checked_in", timestamp: timestamp) }

      it "updates status and checked_in_at" do
        enable_feature_for(booking.hotel, "checkin_confirmation")
        NotificationConfig.create!(hotel: booking.hotel, notification_type: "check_in_confirmation", enabled: true, channels: %w[whatsapp email], settings: {})

        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change(BookingAuditLog, :count).by(1)
          .and have_enqueued_job(WebhookBroadcastJob).with('booking_checked_in', anything)
          .and have_enqueued_job(Notifications::DeliverJob).exactly(2).times

        expect(booking.reload.status).to eq("checked_in")
        expect(booking.checked_in_at).to be_within(1.second).of(timestamp)
        expect(booking.booking_folio).to be_present
        expect(booking.booking_folio.hotel).to eq(booking.hotel)
        expect(booking.booking_folio.folio_number).to be_present

        log = BookingAuditLog.last
        expect(log.action_type).to eq("check_in")
        expect(log.auditable).to eq(booking)
      end

      it "rolls back the folio when payment sync fails" do
        create(:payment_transaction, booking: booking, status: "captured", amount_subunits: 10_000, captured_at: Time.current)

        failed_result = OpenStruct.new(success?: false, error: "posting blocked")
        insert_service = instance_double(Folios::InsertTransaction, call: failed_result)
        allow(Folios::InsertTransaction).to receive(:new).and_return(insert_service)

        result = subject.call

        expect(result.success?).to be false
        expect(result.error).to include("posting blocked")
        expect(booking.reload.status).to eq("confirmed")
        expect(booking.booking_folio).to be_nil
      end

      it "allows different hotels to use the same folio number" do
        other_booking = create(:booking, status: "confirmed")
        BusinessDates::ResetAuthority.call!(hotel: other_booking.hotel, date: timestamp.to_date)
        allow(HotelCounter).to receive(:increment!).and_call_original
        allow(HotelCounter).to receive(:increment!).with(hotel: booking.hotel, type: "folio").and_return(1)
        allow(HotelCounter).to receive(:increment!).with(hotel: other_booking.hotel, type: "folio").and_return(1)

        first_result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call
        second_result = described_class.new(booking: other_booking, status: "checked_in", timestamp: timestamp).call

        expect(first_result.success?).to be true
        expect(second_result.success?).to be true
        expect(booking.reload.booking_folio.folio_number).to eq(1)
        expect(other_booking.reload.booking_folio.folio_number).to eq(1)
      end

      it "optionally records a held security deposit during check-in" do
        result = described_class.new(
          booking: booking,
          status: "checked_in",
          timestamp: timestamp,
          user: user,
          options: {
            security_deposit: {
              amount: "300.00",
              payment_method: "cash",
              external_reference: "DEP-1"
            }
          }
        ).call

        expect(result.success?).to be(true)
        deposit = booking.reload.deposits.sole
        expect(deposit.amount).to eq(300.0)
        expect(deposit.status).to eq("held")
        expect(deposit.hold_type).to eq("security")
        expect(deposit.booking_folio).to eq(booking.booking_folio)
        expect(deposit.transaction_code).to have_attributes(system_key: "security_deposit", code: "SECDEP", gl_account_code: "2030")
        expect(booking.deposit_status).to eq("held")
        expect(BookingAuditLog.last.metadata).to include(
          "security_deposit_id" => deposit.id,
          "security_deposit_amount" => "300.0"
        )
      end

      it "silently no-ops when the booking is already checked in" do
        create(:booking_room, booking: booking, subtotal: 100.0)
        first_result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call
        expect(first_result.success?).to be true
        create(:night_audit, hotel: booking.hotel, business_date: (timestamp + 1.hour).to_date, status: "completed")

        booking.reload
        folio = booking.booking_folio
        checked_in_at = booking.checked_in_at
        guest_registration_number = booking.guest_registration_number
        folio_number = folio.folio_number

        expect {
          second_result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp + 1.hour).call
          expect(second_result.success?).to be true
        }.to change(BookingAuditLog, :count).by(0)
          .and change(BookingFolio, :count).by(0)
          .and change(FolioTransaction, :count).by(0)
          .and have_enqueued_job(WebhookBroadcastJob).exactly(0).times
          .and have_enqueued_job(Notifications::DeliverJob).exactly(0).times

        booking.reload
        expect(booking.checked_in_at).to eq(checked_in_at)
        expect(booking.guest_registration_number).to eq(guest_registration_number)
        expect(booking.booking_folio.folio_number).to eq(folio_number)
      end

      it "repairs a checked-in booking with a missing folio without check-in side effects" do
        checked_in_at = 1.hour.ago
        booking.status_transition_event = "check_in"
        booking.update!(status: "checked_in", checked_in_at: checked_in_at, guest_registration_number: 99)
        create(:booking_room, booking: booking, subtotal: 100.0)
        create(:night_audit, hotel: booking.hotel, business_date: booking.check_in, status: "completed")

        expect {
          result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call
          expect(result.success?).to be true
        }.to change(BookingFolio, :count).by(1)
          .and change(FolioTransaction, :count).by(0)
          .and change(BookingAuditLog, :count).by(0)
          .and have_enqueued_job(WebhookBroadcastJob).exactly(0).times
          .and have_enqueued_job(Notifications::DeliverJob).exactly(0).times

        booking.reload
        expect(booking.checked_in_at.to_i).to eq(checked_in_at.to_i)
        expect(booking.guest_registration_number).to eq(99)
        expect(booking.booking_folio).to be_present
      end

      it "fails when a completed booking is checked in again" do
        booking.status_transition_event = "check_in"
        booking.update!(status: "checked_in")
        booking.status_transition_event = "check_out"
        booking.update!(status: "completed")

        result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call

        expect(result.success?).to be false
        expect(result.error).to include("Cannot check in booking with status completed")
        expect(booking.reload.status).to eq("completed")
      end

      it "fails when a cancelled booking is checked in again" do
        booking.status_transition_event = "cancel"
        booking.update!(status: "cancelled")

        result = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp).call

        expect(result.success?).to be false
        expect(result.error).to include("Cannot check in booking with status cancelled")
        expect(booking.reload.status).to eq("cancelled")
      end

      it "does not require override before the hotel business end closes the check-in date" do
        zone = Time.find_zone("Kuala Lumpur")
        hotel = create(:hotel, time_zone: "Kuala Lumpur")
        booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 18), check_out: Date.new(2026, 5, 19))
        BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.new(2026, 5, 18))

        result = described_class.new(booking: booking, status: "checked_in", timestamp: zone.local(2026, 5, 19, 1, 30)).call

        expect(result.success?).to be true
        expect(booking.reload.status).to eq("checked_in")
      end

      it "requires override when the booking check-in business date is already closed" do
        zone = Time.find_zone("Kuala Lumpur")
        hotel = create(:hotel, time_zone: "Kuala Lumpur")
        booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 18), check_out: Date.new(2026, 5, 19))
        create(:night_audit, hotel: hotel, business_date: Date.new(2026, 5, 18), status: "completed")

        result = described_class.new(booking: booking, status: "checked_in", timestamp: zone.local(2026, 5, 19, 3, 0)).call

        expect(result.success?).to be false
        expect(result.error).to include("Reason required for backdated check-in on closed date 2026-05-18")
        expect(booking.reload.status).to eq("confirmed")
      end
    end

    context "when status is completed" do
      let(:booking) { create(:booking, status: "checked_in") }
      subject { described_class.new(booking: booking, status: "completed", timestamp: timestamp) }

      def create_settled_folio
        folio = create(:booking_folio, booking: booking, status: "open")
        create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
        create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)
        folio
      end

      it "updates status and checked_out_at" do
        folio = create_settled_folio
        enable_feature_for(booking.hotel, "checkout_receipt_review")
        NotificationConfig.create!(
          hotel: booking.hotel,
          notification_type: "post_stay_review_request",
          enabled: true,
          channels: %w[whatsapp],
          settings: { "review_link" => "https://g.page/r/example/review", "send_delay_hours" => 2 }
        )
        NotificationConfig.create!(
          hotel: booking.hotel,
          notification_type: "check_out_receipt_message",
          enabled: true,
          channels: %w[email whatsapp],
          settings: {}
        )

        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change(BookingAuditLog, :count).by(1)
          .and have_enqueued_job(WebhookBroadcastJob).with('booking_completed', anything)
          .and have_enqueued_job(Notifications::DeliverJob).exactly(3).times

        expect(booking.reload.status).to eq("completed")
        expect(booking.checked_out_at).to be_within(1.second).of(timestamp)
        expect(folio.reload.status).to eq("closed")

        log = BookingAuditLog.last
        expect(log.action_type).to eq("check_out")
        expect(log.metadata["folio_id"]).to eq(folio.id)
      end

      it "releases held security deposits and records the release in the checkout audit" do
        folio = create_settled_folio
        deposit = create(
          :deposit,
          booking: booking,
          hotel: booking.hotel,
          booking_folio: folio,
          amount: 150,
          metadata: { "collection_note" => "preserve" }
        )
        booking.update!(deposit_status: "held")

        expect {
          result = described_class.new(
            booking: booking,
            status: "completed",
            timestamp: timestamp,
            user: user,
            options: { security_deposit_release: { method: "card", reference: "AUTH-9" } }
          ).call
          expect(result.success?).to be(true)
        }.not_to change(FolioTransaction, :count)

        expect(deposit.reload).to have_attributes(status: "released", released_at: timestamp)
        expect(deposit.metadata).to include(
          "collection_note" => "preserve",
          "released_by_user_id" => user.id,
          "release_method" => "card",
          "release_reference" => "AUTH-9",
          "source" => "checkout"
        )
        expect(booking.reload.deposit_status).to eq("released")
        expect(BookingAuditLog.last.metadata["security_deposit_release"]).to eq(
          "deposit_ids" => [ deposit.id ],
          "total" => "150.0",
          "method" => "card",
          "reference" => "AUTH-9",
          "released_at" => timestamp.iso8601
        )
      end

      it "leaves held deposits unchanged when release options are absent" do
        folio = create_settled_folio
        deposit = create(:deposit, booking: booking, hotel: booking.hotel, booking_folio: folio)
        booking.update!(deposit_status: "held")

        result = subject.call

        expect(result.success?).to be(true)
        expect(deposit.reload.status).to eq("held")
        expect(booking.reload.deposit_status).to eq("held")
        expect(BookingAuditLog.last.metadata).not_to have_key("security_deposit_release")
      end

      it "rolls back folio closing and checkout when deposit release fails" do
        folio = create_settled_folio
        failure = OpenStruct.new(success?: false, error: "Deposit release failed")
        allow(Deposits::ReleaseHeldDeposits).to receive(:call).and_return(failure)

        result = described_class.new(
          booking: booking,
          status: "completed",
          timestamp: timestamp,
          user: user,
          options: { security_deposit_release: { method: "cash" } }
        ).call

        expect(result.success?).to be(false)
        expect(result.error).to eq("Deposit release failed")
        expect(booking.reload.status).to eq("checked_in")
        expect(folio.reload.status).to eq("open")
      end

      it "checks out a checkout-required booking" do
        folio = create_settled_folio
        booking.transition_status_to!("review_due_out", event: "detect_late_checkout")
        booking.transition_status_to!("checkout_required", event: "reject_late_checkout")

        result = subject.call

        expect(result.success?).to be true
        expect(booking.reload.status).to eq("completed")
        expect(booking.checked_out_at).to be_within(1.second).of(timestamp)
        expect(folio.reload.status).to eq("closed")
      end

      it "does not check out directly from due-out review" do
        folio = create_settled_folio
        booking.transition_status_to!("review_due_out", event: "detect_late_checkout")

        result = subject.call

        expect(result.success?).to be false
        expect(result.error).to eq("Cannot check out booking with status review_due_out")
        expect(booking.reload.status).to eq("review_due_out")
        expect(folio.reload.status).to eq("open")
      end

      it "fails when the folio has an outstanding balance" do
        folio = create(:booking_folio, booking: booking, status: "open")
        create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

        expect {
          result = subject.call
          expect(result.success?).to be(false)
          expect(result.error).to include("outstanding balance")
        }.to change(BookingAuditLog, :count).by(0)
          .and have_enqueued_job(WebhookBroadcastJob).exactly(0).times
          .and have_enqueued_job(Notifications::DeliverJob).exactly(0).times

        expect(booking.reload.status).to eq("checked_in")
        expect(booking.checked_out_at).to be_nil
        expect(folio.reload.status).to eq("open")
      end

      it "fails when the folio has a credit balance" do
        folio = create(:booking_folio, booking: booking, status: "open")
        create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 50.0)

        result = subject.call

        expect(result.success?).to be(false)
        expect(result.error).to include("credit balance")
        expect(booking.reload.status).to eq("checked_in")
        expect(folio.reload.status).to eq("open")
      end

      it "fails without a folio" do
        result = subject.call

        expect(result.success?).to be(false)
        expect(result.error).to eq("Booking has no folio.")
        expect(booking.reload.status).to eq("checked_in")
      end
    end

    context "when status is cancelled" do
      subject { described_class.new(booking: booking, status: "cancelled") }

      it "updates status and releases inventory" do
        inventory_manager = instance_double(Bookings::InventoryManager)
        expect(Bookings::InventoryManager).to receive(:new).with(booking).and_return(inventory_manager)
        expect(inventory_manager).to receive(:release)

        expect {
          result = subject.call
          expect(result.success?).to be true
        }.to change(BookingAuditLog, :count).by(1)
          .and have_enqueued_job(WebhookBroadcastJob).with('booking_cancelled', anything)

        expect(booking.reload.status).to eq("cancelled")

        log = BookingAuditLog.last
        expect(log.action_type).to eq("cancel")
      end

      it "does not release inventory again when already cancelled" do
        booking.status_transition_event = "cancel"
        booking.update!(status: "cancelled")

        expect(Bookings::InventoryManager).not_to receive(:new)

        result = subject.call

        expect(result.success?).to be true
        expect(booking.reload.status).to eq("cancelled")
      end

      it "fails for checked-in bookings" do
        booking.status_transition_event = "check_in"
        booking.update!(status: "checked_in")

        expect(Bookings::InventoryManager).not_to receive(:new)

        result = subject.call

        expect(result.success?).to be false
        expect(result.error).to eq("Cannot cancel booking with status checked_in")
        expect(booking.reload.status).to eq("checked_in")
      end

      it "cancels a no-show review without charges and releases its assigned room" do
        room_type = create(:room_type, hotel: booking.hotel, room_numbers: [ "101" ])
        create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
        room_status = create(:room_status, hotel: booking.hotel, room_type: room_type, room_number: "101", status: "dirty")
        booking.transition_status_to!(
          "review_no_show",
          event: "review_no_show",
          attributes: { no_show_review_business_date: booking.check_in.to_date }
        )

        result = described_class.new(booking: booking, status: "cancelled", user: user, options: { reason: "Guest cancelled" }).call

        expect(result.success?).to be true
        expect(booking.reload.status).to eq("cancelled")
        expect(booking.booking_folio).to be_nil
        expect(room_status.reload.status).to eq("ready")
      end
    end

    it "returns failure for unsupported status" do
      subject = described_class.new(booking: booking, status: "invalid")
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to include("Unsupported status transition")
    end

    it "handles update failures" do
      allow(booking).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(booking))
      allow(booking.errors).to receive(:full_messages).and_return([ "Error" ])

      subject = described_class.new(booking: booking, status: "checked_in")
      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to eq("Error")
    end
    context "late-night check-in scenarios" do
      let(:hotel) { booking.hotel }
      let(:business_date) { booking.check_in }

      before do
        create(:booking_room, booking: booking, subtotal: 100.0)
      end

      context "when booking was finalized as no_show" do
        it "requires the dedicated reinstatement workflow" do
          booking.transition_status_to!(
            "review_no_show",
            event: "review_no_show",
            attributes: { no_show_review_business_date: business_date }
          )
          booking.transition_status_to!("no_show", event: "mark_no_show")

          result = described_class.new(
            booking: booking,
            status: "checked_in",
            timestamp: timestamp,
            user: user,
            options: { override_night_audit: true, reason: "Late arrival" }
          ).call

          expect(result.success?).to be false
          expect(result.error).to include("Cannot check in booking with status no_show")
          expect(booking.reload.status).to eq("no_show")
        end
      end

      context "when check-in is retroactive for a confirmed booking" do
        before do
          BusinessDates::ResetAuthority.call!(hotel: hotel, date: business_date + 1.day)
          create(:night_audit, hotel: hotel, business_date: business_date, status: "completed")
          create(:hotel_business_date, hotel: hotel, business_date: business_date, status: "closed")
        end

        it "posts catch-up charges immediately" do
          options = { override_night_audit: true, reason: "Manual walk-in after audit" }
          subject = described_class.new(booking: booking, status: "checked_in", timestamp: timestamp, user: user, options: options)

          expect {
            result = subject.call
            expect(result.success?).to be true
          }.to change(FolioTransaction, :count).by(1) # 1 catch-up charge (assuming no existing payments)

          catch_up = booking.booking_folio.folio_transactions.charge.first
          expect(catch_up.amount).to eq(100.0)
          expect(catch_up.metadata["posting_source"]).to eq("catch_up")
        end
      end
    end
  end
end
