require "rails_helper"
require "securerandom"

RSpec.describe "Admin::NotificationLogs", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Admin Notification Logs #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "admin-notification-logs-#{token}@example.com") }
  let(:hotel) { create(:hotel, account: account, name: "Notify Hotel #{token}") }

  before { sign_in_as(superadmin) }

  it "lists WhatsApp messages and their errors" do
    create(:notification_delivery, hotel: hotel, channel: "whatsapp", status: "failed", error_message: "Template rejected #{token}")
    create(:notification_delivery, hotel: hotel, channel: "email", notification_type: "invoice_package")

    get "/admin/notification_logs"

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Notification log", "Template rejected #{token}", "Notify Hotel #{token}")
    expect(response.body).not_to include("Invoice package")
  end

  it "lists staff alerts on the staff tab" do
    create(:staff_notification, hotel: hotel, subject: create(:night_audit, hotel: hotel), title: "Alert #{token}")

    get "/admin/notification_logs", params: { tab: "staff" }

    expect(response.body).to include("Alert #{token}", "Warning", "Unread")
  end

  it "shows an empty state inside the table" do
    get "/admin/notification_logs", params: { q: "no-such-#{token}" }

    expect(response.body).to include("No WhatsApp messages found")
  end

  it "shows the data sent for a WhatsApp message" do
    delivery = create(:notification_delivery, hotel: hotel, channel: "whatsapp", payload: { guest_name: "Guest #{token}" })

    get "/admin/notification_logs/#{delivery.id}", params: { tab: "whatsapp" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Guest #{token}", "check_in_confirmation")
  end

  it "shows the full message of a staff alert" do
    alert = create(:staff_notification, hotel: hotel, subject: create(:night_audit, hotel: hotel), message: "Full message #{token}")

    get "/admin/notification_logs/#{alert.id}", params: { tab: "staff" }

    expect(response.body).to include("Full message #{token}")
  end

  it "does not show an email delivery on the WhatsApp tab" do
    delivery = create(:notification_delivery, hotel: hotel, channel: "email")

    get "/admin/notification_logs/#{delivery.id}", params: { tab: "whatsapp" }

    expect(response).to have_http_status(:not_found)
  end
end
