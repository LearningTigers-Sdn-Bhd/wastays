# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Users", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, name: "Hotel Owner", slug: "hotel_owner") }
  let(:permission) { create(:permission, slug: "manage_users") }

  before do
    role.permissions << permission
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/staff" do
    it "renders the staff index" do
      get hotel_users_path(hotel)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Staff Management")
    end
  end

  describe "POST /hotel/:hotel_id/staff" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }

    it "sends a staff invitation" do
      expect {
        post hotel_users_path(hotel), params: { email: "newstaff@example.com", role_id: staff_role.id }
      }.to change(StaffInvitation, :count).by(1)

      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to eq("Invitation sent to newstaff@example.com.")
      expect(StaffInvitation.last.role).to eq(staff_role)
    end

    it "does not grant access until the invite is accepted" do
      expect {
        post hotel_users_path(hotel), params: { email: "newstaff@example.com", role_id: staff_role.id }
      }.not_to change(UserHotelAccess, :count)
    end

    it "refreshes an existing pending invitation" do
      invitation = create(:staff_invitation, account: account, hotel: hotel, role: role, email: "newstaff@example.com", expires_at: 1.day.from_now)

      expect {
        post hotel_users_path(hotel), params: { email: "newstaff@example.com", role_id: staff_role.id }
      }.not_to change(StaffInvitation, :count)

      expect(invitation.reload.role).to eq(staff_role)
      expect(invitation.expires_at).to be > 6.days.from_now
    end

    it "rejects users who already have active access" do
      existing_user = create(:user, account: account, email: "currentstaff@example.com")
      UserHotelAccess.create!(user: existing_user, hotel: hotel, role: staff_role)

      expect {
        post hotel_users_path(hotel), params: { email: existing_user.email, role_id: staff_role.id }
      }.not_to change(StaffInvitation, :count)

      expect(flash[:alert]).to eq("This user already has active access to this property.")
    end

    it "allows inviting users who have deactivated access" do
      existing_user = create(:user, account: account, email: "deactivatedstaff@example.com")
      UserHotelAccess.create!(user: existing_user, hotel: hotel, role: staff_role, deactivated_at: Time.current)

      expect {
        post hotel_users_path(hotel), params: { email: existing_user.email, role_id: staff_role.id }
      }.to change(StaffInvitation, :count).by(1)

      expect(response).to redirect_to(hotel_users_path(hotel))
    end

    it "fails if email is missing" do
      post hotel_users_path(hotel), params: { email: "", role_id: staff_role.id }
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:alert]).to include("Email and Role are required")
    end

    it "rejects roles with manage_account" do
      privileged_permission = create(:permission, slug: "manage_account")
      privileged_role = create(:role, account: account, name: "Privileged Role", slug: "privileged_role")
      privileged_role.permissions << privileged_permission

      expect {
        post hotel_users_path(hotel), params: { email: "owner2@example.com", role_id: privileged_role.id }
      }.not_to change(StaffInvitation, :count)

      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:alert]).to eq("Selected role cannot be assigned.")
    end
  end

  describe "PATCH /hotel/:hotel_id/staff/:id" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:manager_role) { create(:role, account: account, name: "Manager", slug: "manager") }
    let(:other_user) { create(:user, account: account) }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role) }

    it "updates the staff role" do
      patch hotel_user_path(hotel, access), params: { role_id: manager_role.id }
      expect(access.reload.role).to eq(manager_role)
      expect(response).to redirect_to(hotel_users_path(hotel))
    end

    it "rejects non-assignable roles" do
      privileged_permission = create(:permission, slug: "manage_account")
      privileged_role = create(:role, account: account, name: "Privileged Role", slug: "privileged_role")
      privileged_role.permissions << privileged_permission

      patch hotel_user_path(hotel, access), params: { role_id: privileged_role.id }

      expect(access.reload.role).to eq(staff_role)
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:alert]).to eq("Selected role cannot be assigned.")
    end
  end

  describe "DELETE /hotel/:hotel_id/staff/:id" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:other_user) { create(:user, account: account) }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role) }

    it "revokes staff access by deactivating it" do
      expect {
        delete hotel_user_path(hotel, access)
      }.not_to change(UserHotelAccess, :count)

      expect(access.reload.deactivated_at).not_to be_nil
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to eq("Staff access revoked successfully.")
    end

    it "prevents self-revocation" do
      my_access = UserHotelAccess.find_by(user: user, hotel: hotel)
      delete hotel_user_path(hotel, my_access)
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:alert]).to eq("You cannot revoke your own access.")
    end
  end

  describe "PATCH /hotel/:hotel_id/staff/:id/reactivate" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:other_user) { create(:user, account: account) }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role, deactivated_at: Time.current) }

    it "reactivates staff access" do
      patch reactivate_hotel_user_path(hotel, access)
      expect(access.reload.deactivated_at).to be_nil
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to eq("Staff access reactivated successfully.")
    end
  end
end
