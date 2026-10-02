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

    expect(response.body).to include("Connect your Corporate Account")

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

  describe "claiming an existing account" do
    let(:claim_token) { "claim-existing-token" }
    let(:agency_account) { create(:account, :corporate, name: "DREAMY ISLAND") }
    let(:relationship) { create(:hotel_corporate_account, hotel: invitation.hotel, corporate_account: agency_account) }
    let!(:claim) do
      create(:corporate_invitation, account: invitation.account, hotel: invitation.hotel, email: "moon@dreamy.test",
             token_digest: Invitation.digest(claim_token), hotel_corporate_account: relationship)
    end

    it "names the account and does not ask the invitee to choose one" do
      get corporate_invitation_path(claim_token)

      expect(response.body).to include("DREAMY ISLAND", "Create my login")
      expect(response.body).not_to include("user[account_name]")
    end

    it "creates a login inside the existing account and signs them in" do
      expect {
        patch corporate_invitation_path(claim_token), params: {
          user: { name: "Moon", password: "password123", password_confirmation: "password123" }
        }
      }.to change(User, :count).by(1).and change(Account, :count).by(0)

      expect(response).to redirect_to(corporate_dashboard_path)
      expect(User.find_by!(email: "moon@dreamy.test").account).to eq(agency_account)
    end

    it "turns away a claim whose account has been claimed in the meantime" do
      create(:user, :corporate, account: agency_account)

      patch corporate_invitation_path(claim_token), params: {
        user: { name: "Moon", password: "password123", password_confirmation: "password123" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already been claimed")
    end
  end
end
