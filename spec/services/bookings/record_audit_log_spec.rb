# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RecordAuditLog do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "pending") }
  let(:user) { create(:user) }

  describe ".call" do
    it "creates a BookingAuditLog with provided values" do
      expect {
        described_class.call(
          auditable: booking,
          user: user,
          action_type: "update",
          old_value: { "status" => "pending" },
          new_value: { "status" => "confirmed" }
        )
      }.to change(BookingAuditLog, :count).by(1)

      log = BookingAuditLog.last
      expect(log.hotel).to eq(hotel)
      expect(log.auditable).to eq(booking)
      expect(log.user).to eq(user)
      expect(log.action_type).to eq("update")
      expect(log.old_value).to eq({ "status" => "pending" })
      expect(log.new_value).to eq({ "status" => "confirmed" })
    end

    it "extracts values from previous_changes if not provided" do
      booking.transition_status_to!("confirmed", event: "confirm") # This sets previous_changes

      expect {
        described_class.call(auditable: booking, user: user)
      }.to change(BookingAuditLog, :count).by(1)

      log = BookingAuditLog.last
      expect(log.old_value).to include("status" => "pending")
      expect(log.new_value).to include("status" => "confirmed")
    end

    it "does not create a log if there are no changes and values aren't provided" do
      booking.save! # No changes

      expect {
        described_class.call(auditable: booking, user: user)
      }.not_to change(BookingAuditLog, :count)
    end

    it "does not create a log if auditable has no hotel" do
      auditable_without_hotel = double("Auditable", respond_to?: false)

      expect {
        described_class.call(auditable: auditable_without_hotel, user: user)
      }.not_to change(BookingAuditLog, :count)
    end

    it "logs an error and returns false if creation fails" do
      # Create a new BookingAuditLog instance to pass to RecordInvalid
      log_instance = BookingAuditLog.new
      allow(BookingAuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(log_instance))

      expect(Rails.logger).to receive(:error).with(/Failed to create BookingAuditLog/)

      result = described_class.call(
        auditable: booking,
        user: user,
        action_type: "update",
        old_value: { "status" => "pending" },
        new_value: { "status" => "confirmed" }
      )

      expect(result).to be false
    end
  end
end
