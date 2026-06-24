# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::CorporateInvitations", type: :request do
  let(:token) { "corporate-accept-token" }
  let!(:invitation) do
    create(:corporate_invitation, email: "billing@acme.test", token_digest: Invitation.digest(token))
  end

  it "accepts an invitation for a new corporate user" do
    expect {
      patch corporate_invitation_path(token), params: {
        user: {
          account_name: "Acme Sdn Bhd",
          name: "Amina Lee",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    }.to change(User, :count).by(1)
      .and change(HotelCorporateAccount, :count).by(1)

    expect(response).to redirect_to(corporate_dashboard_path)
    user = User.find_by!(email: invitation.email)
    expect(user).to be_corporate
    expect(user.account.name).to eq("Acme Sdn Bhd")
  end

  it "rejects an expired invitation" do
    invitation.update!(expires_at: 1.minute.ago)

    get corporate_invitation_path(token)

    expect(response).to redirect_to(login_path)
  end

  it "requires an existing corporate user to log in before accepting" do
    user = create(:user, :corporate, email: invitation.email)

    get corporate_invitation_path(token)

    expect(response).to redirect_to(login_path)

    post login_path, params: { email: user.email, password: user.password }
    follow_redirect!

    expect(response.body).to include("Connect your Company & Government Account")

    expect {
      patch corporate_invitation_path(token)
    }.to change(HotelCorporateAccount, :count).by(1)

    expect(response).to redirect_to(corporate_dashboard_path)
  end

  it "does not allow a different corporate user to accept the invitation" do
    invited_user = create(:user, :corporate, email: invitation.email)
    other_user = create(:user, :corporate, email: "other-#{invitation.email}")
    post login_path, params: { email: other_user.email, password: other_user.password }

    expect {
      patch corporate_invitation_path(token)
    }.not_to change(HotelCorporateAccount, :count)

    expect(response).to redirect_to(login_path)
    expect(invitation.reload).not_to be_accepted
    expect(session[:user_id]).to eq(other_user.id)
    expect(session[:forwarding_url]).to eq(corporate_invitation_path(token))
    expect(User.find_by!(email: invitation.email)).to eq(invited_user)
  end

  it "does not allow a staff email to accept a corporate invitation" do
    create(:user, email: invitation.email)

    expect {
      patch corporate_invitation_path(token)
    }.not_to change(HotelCorporateAccount, :count)

    expect(response).to redirect_to(login_path)
  end
end
