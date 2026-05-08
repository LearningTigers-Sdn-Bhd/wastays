# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::StaffInvitations", type: :request do
  let(:token) { "accept-token" }
  let!(:invitation) { create(:staff_invitation, email: "newstaff@example.com", token_digest: StaffInvitation.digest(token)) }

  describe "GET /staff-invitations/:token" do
    it "renders the acceptance form" do
      get staff_invitation_path(token)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(CGI.escapeHTML(invitation.hotel.name))
    end

    it "rejects expired invitations" do
      invitation.update!(expires_at: 1.minute.ago)

      get staff_invitation_path(token)

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("This invitation is invalid or has expired.")
    end
  end

  describe "PATCH /staff-invitations/:token" do
    it "creates a new staff user and grants hotel access" do
      expect {
        patch staff_invitation_path(token), params: {
          user: {
            name: "New Staff",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      }.to change(User, :count).by(1).and change(UserHotelAccess, :count).by(1)

      user = User.find_by!(email: invitation.email)
      expect(user.name).to eq("New Staff")
      expect(user.user_hotel_accesses.last.hotel).to eq(invitation.hotel)
      expect(invitation.reload).to be_accepted
      expect(response).to redirect_to(hotel_dashboard_path(invitation.hotel))
    end

    it "grants access to an existing user without changing their password" do
      user = create(:user, email: invitation.email, account: invitation.account, password: "oldpassword")

      expect {
        patch staff_invitation_path(token), params: { user: {} }
      }.to change(UserHotelAccess, :count).by(1).and change(User, :count).by(0)

      expect(user.reload.authenticate("oldpassword")).to be_truthy
      expect(user.hotels).to include(invitation.hotel)
    end
  end
end
