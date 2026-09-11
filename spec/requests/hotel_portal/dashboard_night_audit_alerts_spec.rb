require "rails_helper"

RSpec.describe "Hotel dashboard Night Audit alerts", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |record| record.name = "View Bookings" } }
  let(:manage_night_audit) { Permission.find_or_create_by!(slug: "manage_night_audit") { |record| record.name = "Manage Night Audit" } }

  before do
    role.permissions << view_bookings
    create(:user_hotel_access, hotel:, user:, role:)
    sign_in_as(user)
  end

  it "shows a blocked alert without financial or guest details" do
    create(
      :night_audit,
      hotel:,
      business_date: hotel.current_business_date,
      status: "blocked",
      blocked_details: {
        "missing_folio" => [ { "booking_id" => 1, "guest_name" => "Private Guest" } ],
        "captured_payment_not_synced" => [ { "booking_id" => 2, "amount" => "250.00" } ]
      }
    )

    get hotel_dashboard_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Night Audit needs attention")
    expect(response.body).to include("2 items need attention")
    expect(response.body).to include("The business date did not change")
    expect(response.body).to include('data-tone="destructive"')
    expect(response.body).not_to include("Private Guest", "250.00", "Review Night Audit")
  end

  it "shows the alert while a manual Night Audit waits for issue resolution" do
    create(
      :night_audit,
      hotel:,
      business_date: hotel.current_business_date,
      status: "preparing",
      trigger_mode: "manual",
      blocked_details: { "missed_arrival_not_resolved" => [ { "booking_id" => 1 } ] }
    )

    get hotel_dashboard_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Night Audit needs attention")
    expect(response.body).to include("1 item needs attention")
    expect(response.body).to include("The business date did not change")
  end

  it "shows the review action to staff who manage Night Audit" do
    role.permissions << manage_night_audit
    create(:night_audit, hotel:, business_date: hotel.current_business_date, status: "failed")

    get hotel_dashboard_path(hotel)

    expect(response.body).to include("Night Audit did not finish", "Review Night Audit")
    expect(response.body).to include("data-turbo-frame=\"booking_action_sheet\"")
  end

  it "shows active notification items and an unread count in the hotel navbar" do
    audit = create(:night_audit, hotel:, business_date: hotel.current_business_date, status: "blocked")
    create(:staff_notification, hotel:, recipient: user, subject: audit, title: "Night Audit needs attention")

    get hotel_dashboard_path(hotel)

    expect(response.body).to include("Notifications, 1 unread")
    expect(response.body).to include("Night Audit needs attention")
  end

  it "does not show an alert for warnings on a completed audit" do
    create(
      :night_audit,
      hotel:,
      business_date: hotel.current_business_date,
      status: "completed",
      exceptions: { "open_operational_requests" => [ { "booking_id" => 1 } ] }
    )

    get hotel_dashboard_path(hotel)

    expect(response.body).not_to include("Night Audit needs attention", "Night Audit did not finish")
  end
end
