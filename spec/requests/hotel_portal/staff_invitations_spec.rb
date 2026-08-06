# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::StaffInvitations", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, name: "Hotel Owner", slug: "hotel_owner") }
  let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
  let(:manager_role) { create(:role, account: account, name: "Manager", slug: "manager") }
  let(:permission) { Permission.find_by(slug: 'manage_users') || create(:permission, slug: 'manage_users') }
  let!(:invitation) { create(:staff_invitation, account: account, hotel: hotel, role: staff_role, invited_by_user: user) }

  before do
    role.permissions << permission
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "PATCH /hotel/:hotel_id/staff_invitations/:id" do
    it "updates the invitation role" do
      patch hotel_staff_invitation_path(hotel, invitation), params: { staff_invitation: { role_id: manager_role.id } }
      expect(invitation.reload.role).to eq(manager_role)
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to eq("Invitation role updated successfully.")
    end

    it "rejects non-assignable roles" do
      privileged_permission = Permission.find_by(slug: 'manage_account') || create(:permission, slug: 'manage_account')
      privileged_role = create(:role, account: account, name: "Privileged Role", slug: "privileged_role")
      privileged_role.permissions << privileged_permission

      patch hotel_staff_invitation_path(hotel, invitation), params: { staff_invitation: { role_id: privileged_role.id } }
      expect(invitation.reload.role).to eq(staff_role)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Selected role cannot be assigned")
    end
  end

  describe "GET /hotel/:hotel_id/staff-invitations/:id/edit" do
    it "renders the role sheet" do
      get edit_hotel_staff_invitation_path(hotel, invitation)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Change Invited Role")
    end
  end

  describe "POST /hotel/:hotel_id/staff_invitations/:id/resend" do
    it "resends the invitation and refreshes the token" do
      old_digest = invitation.token_digest
      post resend_hotel_staff_invitation_path(hotel, invitation)
      expect(invitation.reload.token_digest).not_to eq(old_digest)
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to include("Invitation resent")
    end
  end

  describe "DELETE /hotel/:hotel_id/staff_invitations/:id" do
    it "revokes the invitation" do
      expect {
        delete hotel_staff_invitation_path(hotel, invitation)
      }.to change(StaffInvitation, :count).by(-1)
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to eq("Invitation revoked successfully.")
    end
  end
end
