# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::ResetOperationalData do
  let(:account) { create(:account, status: "pending_review") }
  let(:hotel) do
    create(
      :hotel,
      account:,
      status: "ready_to_launch",
      training_started_at: 1.day.ago,
      training_reset_state: "queued"
    )
  end
  let(:actor) { create(:user, account:) }
  let!(:room_type) { create(:room_type, hotel:, quantity: 2, room_numbers: %w[101 102]) }

  before do
    allow(Rails.error).to receive(:report)
    allow(Onboarding::CompleteTraining).to receive(:call) do |hotel:, actor:, decision:|
      hotel.update_columns(
        status: "live",
        training_data_decision: decision,
        training_completed_at: Time.current,
        training_completed_by_id: actor&.id,
        training_reset_state: nil
      )
      Onboarding::CompleteTraining::Result.success(hotel:, submission: nil, readiness: nil)
    end
  end

  it "clears operational records, restores held inventory, and launches through the finalizer" do
    inventory = create(:room_inventory, room_type:, date: Date.current, quantity: 1, available_room_numbers: %w[101 102])
    booking = create(:booking, hotel:, booking_quote: nil, check_in: Date.current, check_out: Date.tomorrow)
    create(:booking_room, booking:, room_type:, room_number: "101")
    guest = create(:guest, created_by_hotel: hotel)
    create(:booking_guest, booking:, guest:, is_primary: true)
    folio = create(:booking_folio, booking:, hotel:)
    create(:folio_transaction, booking_folio: folio, user: actor)
    create(:booking_audit_log, hotel:, auditable: booking, user: actor)
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty", dnd: true)

    result = described_class.call(hotel:, actor:)

    expect(result).to be_success
    expect(hotel.bookings).to be_empty
    expect(BookingFolio.where(id: folio.id)).to be_empty
    expect(FolioTransaction.where(booking_folio_id: folio.id)).to be_empty
    expect(BookingAuditLog.where(hotel_id: hotel.id)).to be_empty
    expect(Guest.where(id: guest.id)).to be_empty
    expect(inventory.reload.quantity).to eq(2)
    expect(room_type.room_statuses.find_by!(room_number: "101")).to have_attributes(status: "ready", dnd: false)
    expect(Onboarding::CompleteTraining).to have_received(:call).with(hotel:, actor:, decision: "reset")
  end

  it "preserves guests that remain linked to another property" do
    other_hotel = create(:hotel)
    guest = create(:guest, created_by_hotel: hotel)
    training_booking = create(:booking, hotel:, booking_quote: nil)
    other_booking = create(:booking, hotel: other_hotel, booking_quote: nil)
    create(:booking_guest, booking: training_booking, guest:, is_primary: true)
    create(:booking_guest, booking: other_booking, guest:, is_primary: true)

    result = described_class.call(hotel:, actor:)

    expect(result).to be_success
    expect(Guest.where(id: guest.id)).to exist
    expect(guest.reload.bookings).to contain_exactly(other_booking)
  end

  it "rolls all cleanup back and marks the reset failed" do
    booking = create(:booking, hotel:, booking_quote: nil)
    allow_any_instance_of(described_class).to receive(:delete_operational_data!).and_wrap_original do |method|
      booking.update_columns(guest_name: "Cleanup changed this")
      raise "cleanup failed"
    end

    result = described_class.call(hotel:, actor:)

    expect(result).not_to be_success
    expect(booking.reload.guest_name).not_to eq("Cleanup changed this")
    expect(hotel.reload).to have_attributes(status: "ready_to_launch", training_reset_state: "failed", training_data_decision: nil)
    expect(OnboardingAuditEvent.where(hotel:, event_type: "training_reset_failed")).to exist
    expect(Rails.error).to have_received(:report).with(instance_of(RuntimeError), hash_including(handled: true))
  end

  it "refuses irreversible gateway activity without deleting anything" do
    booking = create(:booking, hotel:, booking_quote: nil)
    create(:payment_transaction, booking:, booking_quote: nil)

    result = described_class.call(hotel:, actor:)

    expect(result).not_to be_success
    expect(result.error).to include("gateway payment activity")
    expect(Booking.where(id: booking.id)).to exist
    expect(hotel.reload.training_reset_state).to eq("failed")
    expect(Onboarding::CompleteTraining).not_to have_received(:call)
  end

  it "is idempotent after a completed reset" do
    hotel.update!(status: "live", training_data_decision: "reset", training_reset_state: nil)

    result = described_class.call(hotel:, actor:)

    expect(result).to be_success
    expect(Onboarding::CompleteTraining).not_to have_received(:call)
  end
end
