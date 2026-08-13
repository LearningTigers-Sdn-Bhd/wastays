require "rails_helper"

RSpec.describe "HotelPortal::NotificationLogs", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
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

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Notification logs")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include("Check in confirmation")
      expect(page).to have_css("[data-slot='report-page'][data-report='notification-logs']")
      expect(page).to have_css("form[data-controller='auto-submit'][data-turbo-frame='notification_logs_results']")
      expect(page).to have_css("turbo-frame#notification_logs_results")
      expect(page).to have_css(".panel-select-menu select.panel-select-menu__native", count: 3)
      expect(page).to have_no_css("select:not(.panel-select-menu__native)")
      expect(page).to have_css("table.panel-table[data-density='compact'][data-header-style='sentence']")
      expect(page).to have_css("h1", exact_text: "Notification logs")
      caption = page.find(".panel-page-header__caption")
      expect(caption).to have_text(hotel.name)
      expect(caption).to have_text("All notification records")
      expect(page).to have_css("turbo-frame#notification_logs_results", count: 1)
      expect(page).to have_css("turbo-frame#notification_logs_results #notification-logs-export-menu")
      expect(page).to have_css(
        "turbo-frame#notification_logs_results form#notification-logs-filter-form" \
        "[data-controller='auto-submit'][data-turbo-permanent]"
      )
      expect(page).to have_css("select#notification_type option[value='']", exact_text: "All types", visible: :all)
      expect(page).to have_css("select#channel option[value='']", exact_text: "All channels", visible: :all)
      expect(page).to have_css("select#status option[value='']", exact_text: "All statuses", visible: :all)
      expect(page).to have_css(
        "a[href='#{hotel_notification_logs_path(hotel)}'][data-turbo-frame='_top'][data-turbo='false']",
        text: "Reset"
      )
      expect(page).to have_button("Resend", exact: true)
      expect(page).to have_css("button[command='show-modal'][commandfor^='resend-modal-']", text: "Resend")
      expect(page).to have_css("dialog[id^='resend-modal-'][data-controller='panels-ui--dialog']")
      expect(page).to have_css("form[action='#{resend_hotel_notification_log_path(hotel, NotificationDelivery.last)}'][method='post']")
      expect(page).to have_css("textarea[name='resend_reason'][required]")
      expect(page).to have_button("Confirm resend")
      expect(page).to have_no_css("[onclick]")
    end

    it "summarizes notification delivery status for the active filters" do
      booking = create(:booking, hotel: hotel, status: "checked_in")
      %w[sent failed pending skipped].each do |status|
        create(:notification_delivery, hotel: hotel, booking: booking, status: status)
      end

      get hotel_notification_logs_path(hotel)

      page = Capybara.string(response.body)
      expect(page).to have_css("[data-slot='report-metric-strip'][aria-label='Notification delivery summary'] .panel-metric-card", count: 4)
      expect(page).to have_css("[data-slot='report-metric-strip'] .panel-metric-card__detail", count: 4)
      expect(page).to have_text("Total records")
      expect(page).to have_text("Failed")
      expect(page).to have_text("Pending")
      expect(page).to have_text("Sent")
      expect(page).to have_text("Current filters")
    end

    it "generates unique resend field, label, and hint ids without changing the parameter name" do
      booking = create(:booking, hotel: hotel, status: "checked_in")
      deliveries = %w[sent failed].map do |status|
        create(
          :notification_delivery,
          hotel: hotel,
          booking: booking,
          notification_type: "check_in_confirmation",
          channel: "email",
          status: status,
          trigger_event: "booking_checked_in"
        )
      end

      get hotel_notification_logs_path(hotel)

      page = Capybara.string(response.body)
      textareas = page.all("textarea[name='resend_reason']")
      expect(textareas.size).to eq(deliveries.size)
      expect(textareas.map { |textarea| textarea[:id] }).to eq(textareas.map { |textarea| textarea[:id] }.uniq)
      expect(textareas.map { |textarea| textarea[:id] }).to contain_exactly(
        *deliveries.map { |delivery| "resend_#{delivery.id}_resend_reason" }
      )

      textareas.each do |textarea|
        expect(page).to have_css("label##{textarea[:id]}-label[for='#{textarea[:id]}']", text: "Reason")
        expect(textarea["aria-describedby"]).to eq("#{textarea[:id]}-hint")
        expect(page).to have_css("p##{textarea[:id]}-hint", text: "Explain why this notification needs to be resent.")
      end
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

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("timeout")
      expect(response.body).not_to include("No notification logs found")
      expect(page).to have_select("status", selected: "Failed", visible: :all)
      expect(page).to have_link("Export CSV", href: hotel_notification_logs_path(hotel, status: "failed", format: :csv))
      expect(page).to have_link("Export Excel", href: hotel_notification_logs_path(hotel, status: "failed", format: :xlsx))
      expect(page).to have_link("Export PDF", href: hotel_notification_logs_path(hotel, status: "failed", format: :pdf))
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

    it "filters in-stay guest messaging type and shows rule key" do
      booking = create(:booking, hotel: hotel, status: "confirmed")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "in_stay_guest_messaging",
        channel: "email",
        status: "pending",
        trigger_event: "booking_confirmed",
        payload: { guest_name: booking.guest_name, rule_key: "mid_stay" })

      get hotel_notification_logs_path(hotel), params: { notification_type: "in_stay_guest_messaging" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("In stay guest messaging")
      expect(response.body).to include("mid_stay")
    end

    it "denies access without permission" do
      role_permission = RolePermission.find_by(role: role, permission: Permission.find_by!(slug: "view_audit_logs"))
      role_permission.destroy!

      get hotel_notification_logs_path(hotel)

      expect(response).to redirect_to(root_path)
    end

    it "hides resend controls without manage bookings permission" do
      RolePermission.find_by(role: role, permission: Permission.find_by!(slug: "manage_bookings")).destroy!
      booking = create(:booking, hotel: hotel, status: "checked_in")
      create(
        :notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_in_confirmation",
        channel: "email",
        status: "failed",
        trigger_event: "booking_checked_in"
      )

      get hotel_notification_logs_path(hotel)

      page = Capybara.string(response.body)
      expect(response).to have_http_status(:ok)
      expect(page).to have_no_button("Resend")
      expect(page).to have_no_css("dialog[id^='resend-modal-']")
    end

    it "exports the filtered logs as csv, xlsx, and pdf" do
      booking = create(:booking, hotel: hotel, status: "checked_in", confirmation_token: "WS-EXPORT001")
      create(:notification_delivery,
        hotel: hotel,
        booking: booking,
        notification_type: "check_in_confirmation",
        channel: "email",
        status: "failed",
        trigger_event: "booking_checked_in",
        error_message: "Mailbox unavailable")

      get hotel_notification_logs_path(hotel, format: :csv), params: { status: "failed" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("WS-EXPORT001", "Mailbox unavailable")

      get hotel_notification_logs_path(hotel, format: :xlsx), params: { status: "failed" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      expect(response.body).to start_with("PK")

      get hotel_notification_logs_path(hotel, format: :pdf), params: { status: "failed" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
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
