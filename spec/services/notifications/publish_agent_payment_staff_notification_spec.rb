# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::PublishAgentPaymentStaffNotification do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:manage_ar_payments) do
    Permission.find_or_create_by!(slug: "manage_ar_payments") { |permission| permission.name = "Manage AR Payments" }
  end
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:booking) { create(:booking, hotel: hotel, hotel_corporate_account: relationship) }
  let(:submission) do
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking, status: "pending")
  end

  before do
    role.permissions << manage_ar_payments
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
  end

  describe "a slip arriving for review" do
    it "tells everyone who can act on it, and says the clock is paused" do
      described_class.call(booking: booking, event: :submitted, submission: submission)

      notification = StaffNotification.find_by(recipient: user, notification_type: "agent_payment_submitted")
      expect(notification).to have_attributes(severity: "info", hotel_id: hotel.id)
      expect(notification.message).to include("paused until it is reviewed")
    end

    it "links straight to the screen where it is approved or rejected" do
      described_class.call(booking: booking, event: :submitted, submission: submission)

      notification = StaffNotification.find_by(recipient: user, notification_type: "agent_payment_submitted")
      expect(notification.action_path).to include("ar_payment_submission_id=#{submission.id}")
    end

    it "does not raise the same alert twice for the same slip" do
      2.times { described_class.call(booking: booking, event: :submitted, submission: submission) }

      expect(StaffNotification.where(recipient: user, notification_type: "agent_payment_submitted").count).to eq(1)
    end
  end

  describe "rooms released by the sweeper" do
    it "warns the desk that a reservation was cancelled without anyone touching it" do
      described_class.call(booking: booking, event: :released)

      notification = StaffNotification.find_by(recipient: user, notification_type: "agent_booking_released")
      expect(notification).to have_attributes(severity: "warning")
      expect(notification.message).to include("returned to sale")
      expect(notification.action_path).to include("bookings/#{booking.id}")
    end
  end

  it "says nothing to staff who cannot manage AR payments" do
    other = create(:user)
    create(:user_hotel_access, user: other, hotel: hotel, role: create(:role, account: hotel.account))

    described_class.call(booking: booking, event: :released)

    expect(StaffNotification.where(recipient: other)).to be_empty
  end

  it "ignores an event it does not know" do
    expect(described_class.call(booking: booking, event: :something_else)).to be(false)
    expect(StaffNotification.count).to eq(0)
  end
end
