# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ChangeSource do
  let(:actor) { create(:user, name: "Front Desk") }

  it "changes the source and records who changed it from what" do
    booking = create(:booking, source: "phone")

    result = described_class.call(booking:, actor:, source: "booking_com")

    expect(result).to be_success
    expect(booking.reload.source).to eq("booking_com")
    expect(booking).to be_ota_booking
    log = BookingAuditLog.find_by!(auditable: booking, action_type: "source_changed")
    expect(log).to have_attributes(user: actor, category: "stay", old_value: { "source" => "phone" }, new_value: { "source" => "booking_com" })
  end

  it "accepts a source spelled the way a channel writes it" do
    booking = create(:booking, source: "phone")

    expect(described_class.call(booking:, actor:, source: "Booking.com ")).to be_success
    expect(booking.reload.source).to eq("booking_com")
  end

  it "refuses a system source" do
    booking = create(:booking, source: "phone")

    result = described_class.call(booking:, actor:, source: "channex")

    expect(result).not_to be_success
    expect(result.errors).to contain_exactly("Channex is not an available booking source.")
    expect(booking.reload.source).to eq("phone")
  end

  it "refuses an inactive source" do
    create(:booking_source, key: "old_agency", label: "Old Agency", kind: "manual", active: false)
    booking = create(:booking, source: "phone")

    expect(described_class.call(booking:, actor:, source: "old_agency")).not_to be_success
    expect(booking.reload.source).to eq("phone")
  end

  it "refuses a blank or unchanged source" do
    booking = create(:booking, source: "phone")

    expect(described_class.call(booking:, actor:, source: "").errors).to contain_exactly("Choose a booking source.")
    expect(described_class.call(booking:, actor:, source: "phone").errors).to contain_exactly("The booking is already recorded as Phone.")
    expect(BookingAuditLog.where(auditable: booking, action_type: "source_changed")).not_to exist
  end

  describe "locked bookings" do
    it "refuses a channel manager booking" do
      booking = create(:booking, source: "agoda", channel_manager_reference: "CHX-1")

      result = described_class.call(booking:, actor:, source: "phone")

      expect(result.errors).to contain_exactly("This booking came from the channel manager, which owns its source.")
      expect(booking.reload.source).to eq("agoda")
    end

    it "refuses a booking with channel settlements" do
      allocation = create(:channel_settlement_allocation)
      booking = allocation.booking

      result = described_class.call(booking:, actor:, source: "phone")

      expect(result.errors).to contain_exactly("This booking has channel settlements recorded against its source.")
    end

    it "refuses a booking with an OTA billing party" do
      booking = create(:booking, source: "agoda")
      create(:booking_billing_party, booking:, party_kind: "ota", hotel_corporate_account: nil,
        booking_source: BookingSource.find_by!(key: "agoda"))

      result = described_class.call(booking:, actor:, source: "phone")

      expect(result.errors).to contain_exactly("This booking has an OTA billing party for its current source.")
    end

    it "refuses a booking with an issued e-invoice but not a cancelled one" do
      booking = create(:booking, source: "phone")
      submission = create(:e_invoice_submission, booking:, hotel: booking.hotel, status: "valid")

      expect(described_class.call(booking:, actor:, source: "email").errors)
        .to contain_exactly("An e-invoice has already been issued for this booking.")

      submission.update!(status: "cancelled")
      expect(described_class.call(booking:, actor:, source: "email")).to be_success
    end
  end
end
