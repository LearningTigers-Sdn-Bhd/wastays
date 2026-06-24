# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::CorporateAccounts", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:permission) { Permission.find_by(slug: "manage_corporate_accounts") || create(:permission, name: "Manage Corporate Accounts", slug: "manage_corporate_accounts") }

  before do
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "lists only relationships belonging to the current hotel" do
    visible = create(:hotel_corporate_account, hotel: hotel)
    hidden = create(:hotel_corporate_account)

    get hotel_corporate_accounts_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include(visible.corporate_account.name)
    expect(response.body).not_to include(hidden.corporate_account.name)
  end

  it "renders the invitation form in the offcanvas frame" do
    get new_hotel_corporate_account_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
    expect(response.body).to include("Corporate contact email")
    expect(response.body).not_to include("Company name")
  end

  it "creates a corporate invitation and completes the offcanvas" do
    expect {
      post hotel_corporate_accounts_path(hotel), params: {
        corporate_invitation: {
          email: "billing@acme.test",
          relationship_type: "standard",
          credit_currency: "MYR"
        }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }
    }.to change(CorporateInvitation, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_offcanvas"')
    expect(response.body).to include(hotel_corporate_accounts_path(hotel))
    expect(CorporateInvitation.last.metadata).to include(
      "relationship_type" => "standard",
      "credit_currency" => "MYR"
    )
  end

  it "keeps service errors and submitted values inside the offcanvas" do
    create(:user, email: "staff@example.com")

    post hotel_corporate_accounts_path(hotel), params: {
      corporate_invitation: {
        email: "staff@example.com",
        corporate_type: "agency",
        relationship_type: "direct_bill",
        credit_currency: "MYR"
      }
    }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("hotel staff")
    expect(response.body).to include("staff@example.com")
    expect(response.body).to include("agency")
    expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
  end

  it "cannot suspend another hotel's relationship" do
    relationship = create(:hotel_corporate_account)

    patch suspend_hotel_corporate_account_path(hotel, relationship)

    expect(response).to have_http_status(:not_found)
    expect(relationship.reload).to be_active
  end

  it "resends an expired unaccepted invitation with a new token" do
    invitation = create(
      :corporate_invitation,
      hotel: hotel,
      account: account,
      invited_by_user: user,
      expires_at: 1.minute.ago
    )
    old_digest = invitation.token_digest

    post resend_hotel_corporate_invitation_path(hotel, invitation)

    expect(response).to redirect_to(hotel_corporate_accounts_path(hotel))
    expect(invitation.reload.token_digest).not_to eq(old_digest)
    expect(invitation).to be_pending
  end

  it "revokes an unaccepted invitation" do
    invitation = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user)

    expect {
      delete hotel_corporate_invitation_path(hotel, invitation)
    }.to change(CorporateInvitation, :count).by(-1)
  end
end
