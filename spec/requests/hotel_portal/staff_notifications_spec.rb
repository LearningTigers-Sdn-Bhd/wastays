require "rails_helper"

RSpec.describe "Hotel staff notifications", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    create(:user_hotel_access, hotel:, user:, role:)
    sign_in_as(user)
  end

  it "marks the current recipient notification as read and follows its hotel path" do
    notification = create(
      :staff_notification,
      hotel:,
      recipient: user,
      subject: create(:night_audit, hotel:, business_date: hotel.current_business_date, status: "blocked"),
      action_path: hotel_dashboard_path(hotel)
    )

    patch hotel_staff_notification_path(hotel, notification)

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
    expect(notification.reload.read_at).to be_present
  end

  it "does not expose another recipient notification" do
    notification = create(
      :staff_notification,
      hotel:,
      subject: create(:night_audit, hotel:, business_date: hotel.current_business_date, status: "blocked")
    )

    patch hotel_staff_notification_path(hotel, notification)

    expect(response).to have_http_status(:not_found)
    expect(notification.reload.read_at).to be_nil
  end
end
