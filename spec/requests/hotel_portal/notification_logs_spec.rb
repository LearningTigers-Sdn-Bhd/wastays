require "rails_helper"

RSpec.describe "HotelPortal::NotificationLogs", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    Permission.find_or_create_by!(slug: "view_audit_logs") { |permission| permission.name = "View Audit Logs" }
    Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "view_audit_logs"))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_bookings"))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/notification_logs" do
    it "renders notification logs page" do
      booking = create(:booking, hotel: hotel, status: "checked_in")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_in_confirmation",
        channel: "whatsapp",
        status: "sent",
        trigger_event: "booking_checked_in",
        payload: { guest_name: booking.guest_name })

      get hotel_notification_logs_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Notification Logs")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include("Check in confirmation")
    end

    it "filters by status" do
      booking = create(:booking, hotel: hotel, status: "checked_in")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_in_confirmation",
        channel: "email",
        status: "sent",
        trigger_event: "booking_checked_in")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_in_confirmation",
        channel: "whatsapp",
        status: "failed",
        trigger_event: "booking_checked_in",
        error_message: "timeout")

      get hotel_notification_logs_path(hotel), params: { status: "failed" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("timeout")
      expect(response.body).not_to include("No notification logs found")
    end

    it "filters by search query" do
      matching_booking = create(:booking, hotel: hotel, status: "checked_in", guest_name: "Aisyah", confirmation_token: "WS-MATCH123")
      other_booking = create(:booking, hotel: hotel, status: "checked_in", guest_name: "Brandon", confirmation_token: "WS-OTHER999")

      create(:notification_delivery,
        hotel: hotel,
        booking: matching_booking,
        notification_type: "check_in_confirmation",
        channel: "email",
        status: "sent",
        trigger_event: "booking_checked_in")
      create(:notification_delivery,
        hotel: hotel,
        booking: other_booking,
        notification_type: "check_in_confirmation",
        channel: "whatsapp",
        status: "sent",
        trigger_event: "booking_checked_in")

      get hotel_notification_logs_path(hotel), params: { query: "WS-MATCH123" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WS-MATCH123")
      expect(response.body).not_to include("WS-OTHER999")
    end

    it "shows pre-arrival type and stage in logs" do
      booking = create(:booking, hotel: hotel, status: "confirmed")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "pre_arrival_notification",
        channel: "email",
        status: "pending",
        trigger_event: "booking_confirmed",
        payload: { guest_name: booking.guest_name, stage: "d2" })

      get hotel_notification_logs_path(hotel), params: { notification_type: "pre_arrival_notification" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pre arrival notification")
      expect(response.body).to include("d2")
    end

    it "filters check-out receipt message type" do
      booking = create(:booking, hotel: hotel, status: "completed")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_out_receipt_message",
        channel: "email",
        status: "sent",
        trigger_event: "booking_completed",
        payload: { guest_name: booking.guest_name })

      get hotel_notification_logs_path(hotel), params: { notification_type: "check_out_receipt_message" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Check out receipt message")
      expect(response.body).to include(booking.confirmation_token)
    end

    it "denies access without permission" do
      role_permission = RolePermission.find_by(role: role, permission: Permission.find_by!(slug: "view_audit_logs"))
      role_permission.destroy!

      get hotel_notification_logs_path(hotel)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /hotel/:hotel_id/notification_logs/:id/resend" do
    it "creates a new pending delivery with resend metadata" do
      booking = create(:booking, hotel: hotel, status: "checked_in")
      original = create(
        :notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_in_confirmation",
        channel: "whatsapp",
        status: "failed",
        trigger_event: "booking_checked_in",
        payload: { guest_name: booking.guest_name }
      )

      expect {
        post resend_hotel_notification_log_path(hotel, original), params: { resend_reason: "Guest requested retry" }
      }.to change(NotificationDelivery, :count).by(1)
        .and have_enqueued_job(Notifications::DeliverJob).exactly(1).times

      resent = NotificationDelivery.order(:id).last
      expect(resent.trigger_event).to eq("manual_resend")
      expect(resent.status).to eq("pending")
      expect(resent.payload["resend_reason"]).to eq("Guest requested retry")
      expect(response).to redirect_to(hotel_notification_logs_path(hotel))
    end
  end
end
