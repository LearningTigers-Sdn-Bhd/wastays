# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Guest magic-link sessions", type: :request do
  let(:guest) { create(:guest, email: "jane@example.com") }

  it "sends a login link through the shared issuer" do
    expect {
      post guest_request_magic_link_path, params: { email: guest.email }
    }.to have_enqueued_mail(GuestMailer, :magic_link)

    expect(response).to redirect_to(guest_login_path(email_sent: true))
    expect(guest.reload.magic_token_digest).to be_present
  end

  it "signs the guest in once and redirects to the dashboard" do
    token = guest.generate_magic_token!

    get guest_verify_path, params: { token: token }

    expect(response).to redirect_to(guest_dashboard_path)
    expect(session[:guest_id]).to eq(guest.id)
    expect(guest.reload.magic_token_digest).to be_nil

    delete guest_logout_path
    get guest_verify_path, params: { token: token }

    expect(response).to redirect_to(guest_login_path)
    expect(session[:guest_id]).to be_nil
  end

  it "rejects an expired link" do
    token = guest.generate_magic_token!
    guest.update!(magic_token_expires_at: 1.minute.ago)

    get guest_verify_path, params: { token: token }

    expect(response).to redirect_to(guest_login_path)
    expect(session[:guest_id]).to be_nil
  end
end
