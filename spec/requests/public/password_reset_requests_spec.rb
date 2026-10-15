# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::PasswordResetRequests", type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:user) { create(:user, account:, password: "password123456", password_confirmation: "password123456") }
  let(:generic_notice) { "If that email has an account, we've sent a link to reset your password." }

  it "renders the form" do
    get forgot_password_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Send reset link")
  end

  it "emails a reset link to a known user" do
    expect { post forgot_password_path, params: { email: user.email.upcase } }
      .to have_enqueued_mail(OwnerPasswordResetMailer, :forgot)

    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to eq(generic_notice)
    expect(user.owner_password_resets.count).to eq(1)
  end

  it "gives the same answer for unknown emails and sends nothing" do
    expect { post forgot_password_path, params: { email: "nobody@example.com" } }
      .not_to have_enqueued_mail

    expect(response).to redirect_to(login_path)
    expect(flash[:notice]).to eq(generic_notice)
  end

  it "sends nothing for suspended accounts" do
    account.update!(status: "suspended")

    expect { post forgot_password_path, params: { email: user.email } }.not_to have_enqueued_mail
    expect(flash[:notice]).to eq(generic_notice)
  end

  it "does not send again inside the cooldown" do
    post forgot_password_path, params: { email: user.email }

    expect { post forgot_password_path, params: { email: user.email } }.not_to have_enqueued_mail
  end

  it "lets the user set a new password from the emailed link" do
    token = nil
    allow(OwnerPasswordReset).to receive(:issue!).and_wrap_original { |m, u| token = m.call(u) }
    post forgot_password_path, params: { email: user.email }

    patch owner_password_reset_path(token), params: { password: "BrandNewPass123!", password_confirmation: "BrandNewPass123!" }

    expect(response).to redirect_to(login_path)
    expect(user.reload.authenticate("BrandNewPass123!")).to be_truthy
  end
end
