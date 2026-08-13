# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Users", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, name: "Hotel Owner", slug: "hotel_owner") }
  let(:permission) { Permission.find_by(slug: 'manage_users') || create(:permission, slug: 'manage_users') }

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

    context "an invitation queued during onboarding that was never emailed" do
      let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }

      it "is listed as not sent rather than waiting on the invitee" do
        create(:staff_invitation, :held, account: account, hotel: hotel, role: staff_role,
                                         invited_by_user: user, email: "held@example.com")

        get hotel_users_path(hotel)

        expect(response.body).to include("held@example.com", "Not sent", "Send invitation")
        expect(response.body).not_to include("Resend invitation")
      end

      # Its seven days have not started, so the row must not disappear a week
      # after the owner listed the person.
      it "stays on the page past the unstarted expiry window" do
        create(:staff_invitation, :held, account: account, hotel: hotel, role: staff_role,
                                         invited_by_user: user, email: "held@example.com",
                                         expires_at: 2.days.ago)

        get hotel_users_path(hotel)

        expect(response.body).to include("held@example.com")
      end
    end

    it "lists staff with their status and role as plain text" do
      staff_role = create(:role, account: account, name: "Front Desk", slug: "front_desk")
      member = create(:user, account: account, name: "Aisha Rahman")
      UserHotelAccess.create!(user: member, hotel: hotel, role: staff_role)

      get hotel_users_path(hotel)

      expect(response.body).to include("Aisha Rahman")
      expect(response.body).to include("Front Desk")
      expect(response.body).to include("Active")
    end

    it "shows revoked access as revoked" do
      staff_role = create(:role, account: account, name: "Front Desk", slug: "front_desk")
      member = create(:user, account: account)
      UserHotelAccess.create!(user: member, hotel: hotel, role: staff_role, deactivated_at: Time.current)

      get hotel_users_path(hotel)

      expect(response.body).to include("Revoked")
    end

    it "renders no role select on the listing" do
      get hotel_users_path(hotel)

      expect(response.body).not_to match(/<select[^>]*name="role_id"/)
    end

    it "shows an empty state when nobody but the current user has access" do
      UserHotelAccess.find_by(user: user, hotel: hotel).destroy!
      superadmin = create(:user, account: account, role: "superadmin")
      sign_in_as(superadmin)

      get hotel_users_path(hotel)

      expect(response.body).to include("No staff have access yet")
    end
  end

  describe "GET /hotel/:hotel_id/staff/new" do
    it "renders the invite sheet" do
      get new_hotel_user_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Invite Staff Member")
    end

    # The sheet renders without a layout, so an old bookmark pointing straight at
    # it would land on a bare dialog. Send those to the list instead.
    it "sends the legacy deep link to the list rather than the bare sheet" do
      get "/hotel/#{hotel.to_param}/staff/new"

      expect(response).to redirect_to(hotel_users_path(hotel))
    end
  end

  describe "GET /hotel/:hotel_id/staff/:id/edit" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:other_user) { create(:user, account: account, name: "Aisha Rahman") }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role) }

    it "renders the access sheet with the role control" do
      get edit_hotel_user_path(hotel, access)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit Access")
      expect(response.body).to include("Aisha Rahman")
      expect(response.body).to include("Front Desk")
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

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already has active access")
    end

    it "rejects an email belonging to a corporate user" do
      corporate_user = create(:user, :corporate)

      expect {
        post hotel_users_path(hotel), params: { email: corporate_user.email, role_id: staff_role.id }
      }.not_to change(StaffInvitation, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("corporate account")
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

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Email and role are required")
    end

    it "rejects roles with manage_account" do
      privileged_role = create_privileged_role

      expect {
        post hotel_users_path(hotel), params: { email: "owner2@example.com", role_id: privileged_role.id }
      }.not_to change(StaffInvitation, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Selected role cannot be assigned")
    end
  end

  describe "PATCH /hotel/:hotel_id/staff/:id" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:manager_role) { create(:role, account: account, name: "Manager", slug: "manager") }
    let(:other_user) { create(:user, account: account) }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role) }

    it "updates the staff role" do
      patch hotel_user_path(hotel, access), params: { user_hotel_access: { role_id: manager_role.id } }
      expect(access.reload.role).to eq(manager_role)
      expect(response).to redirect_to(hotel_users_path(hotel))
    end

    it "never changes access status" do
      access.deactivate!

      patch hotel_user_path(hotel, access), params: { user_hotel_access: { role_id: manager_role.id } }

      expect(access.reload.role).to eq(manager_role)
      expect(access.deactivated_at).not_to be_nil
    end

    it "rejects non-assignable roles" do
      privileged_role = create_privileged_role

      patch hotel_user_path(hotel, access), params: { user_hotel_access: { role_id: privileged_role.id } }

      expect(access.reload.role).to eq(staff_role)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "prevents editing your own access" do
      my_access = UserHotelAccess.find_by(user: user, hotel: hotel)

      patch hotel_user_path(hotel, my_access), params: { user_hotel_access: { role_id: manager_role.id } }

      expect(my_access.reload.role).to eq(role)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # Anyone reaching this page through a hotel role is themselves an account
    # manager, so only a superadmin — who has every permission without holding an
    # access row — can be looking at a genuinely sole account manager.
    context "as a superadmin" do
      let(:owner_role) { create(:role, account: account, name: "Owner", slug: "owner") }
      let!(:owner_access) do
        owner_role.permissions << manage_account_permission
        UserHotelAccess.create!(user: create(:user, account: account), hotel: hotel, role: owner_role)
      end

      before { sign_in_as(create(:user, account: account, role: "superadmin")) }

      it "refuses to demote the last account manager to a role without account management" do
        patch hotel_user_path(hotel, owner_access),
              params: { user_hotel_access: { role_id: staff_role.id, active: "1" } }

        expect(owner_access.reload.role).to eq(owner_role)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /hotel/:hotel_id/staff/:id/status" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:other_user) { create(:user, account: account, name: "Aisha Rahman") }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role) }

    it "revokes access without deleting the record" do
      expect {
        patch status_hotel_user_path(hotel, access), params: { active: "0" }
      }.not_to change(UserHotelAccess, :count)

      expect(access.reload.deactivated_at).not_to be_nil
      expect(response).to redirect_to(hotel_users_path(hotel))
      expect(flash[:notice]).to eq("Aisha Rahman's access was revoked.")
    end

    it "restores revoked access" do
      access.deactivate!

      patch status_hotel_user_path(hotel, access), params: { active: "1" }

      expect(access.reload.deactivated_at).to be_nil
      expect(flash[:notice]).to eq("Aisha Rahman's access was restored.")
    end

    it "leaves the role untouched" do
      patch status_hotel_user_path(hotel, access), params: { active: "0" }

      expect(access.reload.role).to eq(staff_role)
    end

    it "prevents revoking your own access" do
      my_access = UserHotelAccess.find_by(user: user, hotel: hotel)

      patch status_hotel_user_path(hotel, my_access), params: { active: "0" }

      expect(my_access.reload.deactivated_at).to be_nil
      expect(flash[:alert]).to eq("You cannot change your own access.")
    end

    context "as a superadmin" do
      let(:owner_role) { create(:role, account: account, name: "Owner", slug: "owner") }
      let!(:owner_access) do
        owner_role.permissions << manage_account_permission
        UserHotelAccess.create!(user: create(:user, account: account), hotel: hotel, role: owner_role)
      end

      before { sign_in_as(create(:user, account: account, role: "superadmin")) }

      it "refuses to revoke the last account manager" do
        patch status_hotel_user_path(hotel, owner_access), params: { active: "0" }

        expect(owner_access.reload.deactivated_at).to be_nil
        expect(flash[:alert]).to include("only person who can manage this account")
      end

      it "allows revoking an account manager once another one exists" do
        UserHotelAccess.create!(user: create(:user, account: account), hotel: hotel, role: owner_role)

        patch status_hotel_user_path(hotel, owner_access), params: { active: "0" }

        expect(owner_access.reload.deactivated_at).not_to be_nil
        expect(response).to redirect_to(hotel_users_path(hotel))
      end
    end
  end

  describe "DELETE /hotel/:hotel_id/staff/:id" do
    let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
    let(:other_user) { create(:user, account: account) }
    let!(:access) { UserHotelAccess.create!(user: other_user, hotel: hotel, role: staff_role) }

    # manage_users opens this page; permanent deletion is gated separately on
    # manage_account, so a manager sees the table but never the delete action.
    context "without account management" do
      it "is refused" do
        expect {
          delete hotel_user_path(hotel, access)
        }.not_to change(UserHotelAccess, :count)

        expect(flash[:alert]).to eq("You are not authorized to perform this action.")
      end
    end

    context "with account management" do
      before { role.permissions << manage_account_permission }

      it "permanently deletes the access" do
        expect {
          delete hotel_user_path(hotel, access)
        }.to change(UserHotelAccess, :count).by(-1)

        expect(response).to redirect_to(hotel_users_path(hotel))
        expect(flash[:notice]).to include("permanently deleted")
      end

      it "leaves the user record intact" do
        expect {
          delete hotel_user_path(hotel, access)
        }.not_to change(User, :count)
      end

      it "prevents deleting your own access" do
        my_access = UserHotelAccess.find_by(user: user, hotel: hotel)

        expect {
          delete hotel_user_path(hotel, my_access)
        }.not_to change(UserHotelAccess, :count)

        expect(flash[:alert]).to eq("You cannot delete your own access.")
      end
    end

    context "as a superadmin facing the sole account manager" do
      let(:owner_role) { create(:role, account: account, name: "Owner", slug: "owner") }
      let!(:owner_access) do
        owner_role.permissions << manage_account_permission
        UserHotelAccess.create!(user: create(:user, account: account), hotel: hotel, role: owner_role)
      end

      before { sign_in_as(create(:user, account: account, role: "superadmin")) }

      it "refuses to delete the last account manager" do
        expect {
          delete hotel_user_path(hotel, owner_access)
        }.not_to change(UserHotelAccess, :count)

        expect(flash[:alert]).to include("only person who can manage this account")
      end
    end
  end

  def manage_account_permission
    Permission.find_by(slug: "manage_account") || create(:permission, slug: "manage_account", name: "Manage Account")
  end

  def create_privileged_role
    privileged_role = create(:role, account: account, name: "Privileged Role", slug: "privileged_role")
    privileged_role.permissions << manage_account_permission
    privileged_role
  end
end
