# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel notification log filters", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, email: "notification-manager@example.com") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel owner") }

  before do
    driven_by(:cuprite)

    %w[view_audit_logs manage_bookings].each do |slug|
      permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    failed_booking = create(:booking, hotel: hotel, confirmation_token: "WS-FAILED-FILTER")
    create(
      :notification_delivery,
      hotel: hotel,
      booking: failed_booking,
      notification_type: "check_in_confirmation",
      channel: "email",
      status: "failed",
      trigger_event: "booking_checked_in"
    )
    sent_booking = create(:booking, hotel: hotel, confirmation_token: "WS-SENT-FILTER")
    create(
      :notification_delivery,
      hotel: hotel,
      booking: sent_booking,
      notification_type: "check_in_confirmation",
      channel: "email",
      status: "sent",
      trigger_event: "booking_checked_in"
    )

    sign_in_through_ui(user)
  end

  it "preserves filter focus while updating exports and results through the Turbo frame" do
    visit hotel_notification_logs_path(hotel)

    expect(page).to have_content("WS-FAILED-FILTER")
    expect(page).to have_content("WS-SENT-FILTER")
    page.execute_script("window.__notificationFilterDocumentMarker = 'same-document'")
    page.execute_script("window.__notificationFilterForm = document.getElementById('notification-logs-filter-form')")

    search = find_field("Search")
    search.click
    search.send_keys("WS-FAILED-FILTER")
    expect(page.evaluate_script("document.activeElement.id")).to eq("query")

    expect(page).to have_link(
      "Export CSV",
      href: hotel_notification_logs_path(hotel, query: "WS-FAILED-FILTER", format: :csv),
      visible: :all
    )
    expect(page.evaluate_script("document.getElementById('notification-logs-filter-form') === window.__notificationFilterForm")).to be(true)
    wait_until("expected search focus to survive the Turbo frame response") do
      page.evaluate_script("document.activeElement.id") == "query"
    end
    expect(find_field("Search").value).to eq("WS-FAILED-FILTER")

    find("#status-trigger").click
    expect(page).to have_css("#status-listbox:popover-open")
    find("#status-listbox [role='option']", text: "Failed").click

    expect(page).to have_link(
      "Export CSV",
      href: hotel_notification_logs_path(hotel, query: "WS-FAILED-FILTER", status: "failed", format: :csv),
      visible: :all
    )
    wait_until("expected status trigger focus to survive the Turbo frame response") do
      page.evaluate_script("document.activeElement.id") == "status-trigger"
    end
    expect(find_field("Search").value).to eq("WS-FAILED-FILTER")
    expect(page).to have_content("WS-FAILED-FILTER")
    expect(page).to have_no_content("WS-SENT-FILTER")
    expect(page.evaluate_script("window.__notificationFilterDocumentMarker")).to eq("same-document")
    expect(page).to have_current_path(hotel_notification_logs_path(hotel))

    click_link "Reset"

    expect(page).to have_current_path(hotel_notification_logs_path(hotel))
    expect(URI.parse(page.current_url).query).to be_nil
    expect(find_field("Search").value).to eq("")
    expect(page).to have_css("#status-trigger .panel-select-menu__value", exact_text: "All statuses")
    expect(page).to have_select("status", selected: "All statuses", visible: :all)
    expect(page).to have_content("WS-FAILED-FILTER")
    expect(page).to have_content("WS-SENT-FILTER")
    expect(page).to have_link(
      "Export CSV",
      href: hotel_notification_logs_path(hotel, format: :csv),
      visible: :all
    )
    expect(page.evaluate_script("window.__notificationFilterDocumentMarker")).to be_nil
  end

  it "submits a resend reason from a non-first notification dialog" do
    visit hotel_notification_logs_path(hotel)

    row = find("tr", text: "WS-FAILED-FILTER")
    dialog_id = row.find_button("Resend")[:commandfor]
    resend_reason = "Retry after resolving the delivery issue"
    row.find_button("Resend").click

    within("dialog##{dialog_id}") do
      fill_in "Reason", with: resend_reason
      click_button "Confirm resend"
    end

    expect(page).to have_current_path(hotel_notification_logs_path(hotel))
    resent = NotificationDelivery.find_by!(trigger_event: "manual_resend")
    expect(resent.booking.confirmation_token).to eq("WS-FAILED-FILTER")
    expect(resent.payload["resend_reason"]).to eq(resend_reason)
  end
end
