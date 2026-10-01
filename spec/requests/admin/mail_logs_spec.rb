require "rails_helper"
require "securerandom"

RSpec.describe "Admin::MailLogs", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:account) { create(:account, name: "Admin Mail Logs #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "admin-mail-logs-#{token}@example.com") }

  before { sign_in_as(superadmin) }

  it "lists emails with status and error" do
    MailEvent.create!(mailer: "GuestMailer", mail_action: "booking_confirmation", subject: "Subject #{token}", recipients: "guest-#{token}@example.com", status: "sent", sent_at: Time.current)
    MailEvent.create!(mailer: "SystemMailer", subject: "Failed #{token}", recipients: "ops-#{token}@example.com", status: "failed", error_message: "SMTP down", sent_at: Time.current)

    get "/admin/mail_logs"

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Mail log", "Subject #{token}", "guest-#{token}@example.com", "SMTP down")
  end

  it "filters by status" do
    MailEvent.create!(mailer: "GuestMailer", subject: "Kept #{token}", status: "sent", sent_at: Time.current)
    MailEvent.create!(mailer: "GuestMailer", subject: "Hidden #{token}", status: "failed", sent_at: Time.current)

    get "/admin/mail_logs", params: { status: "sent" }

    expect(response.body).to include("Kept #{token}")
    expect(response.body).not_to include("Hidden #{token}")
  end

  it "shows an empty state" do
    get "/admin/mail_logs", params: { q: "no-such-#{token}" }

    expect(response.body).to include("No emails found")
  end
end
