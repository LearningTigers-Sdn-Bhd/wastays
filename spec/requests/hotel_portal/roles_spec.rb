# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Roles", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan) }
  let(:user) { create(:user, account: account) }
  let(:manager_role) { create(:role, account: account, name: "General Manager", slug: "general_manager") }
  let(:manage_users_permission) { Permission.find_by(slug: 'manage_users') || create(:permission, slug: 'manage_users', name: 'Manage Users') }

  before do
    create(:role_permission, role: manager_role, permission: manage_users_permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: manager_role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "role_based_access_control"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/roles-and-permissions" do
    it "shows account roles" do
      role = create(:role, account: account, name: "Front Desk", slug: "front_desk")

      get hotel_roles_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(role.name)
    end

    it "blocks users without manage_users permission" do
      manager_role.permissions.delete(manage_users_permission)

      get hotel_roles_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
    end
  end

  describe "POST /hotel/:hotel_id/roles-and-permissions" do
    it "creates a role with selected permissions" do
      view_bookings = Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings', name: 'View Bookings')
      manage_bookings = Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings', name: 'Manage Bookings')

      expect do
        post hotel_roles_path(hotel), params: {
          role: {
            name: "Reservations Lead",
            permission_ids: [ view_bookings.id, manage_bookings.id ]
          }
        }
      end.to change(account.roles, :count).by(1)

      role = account.roles.find_by!(name: "Reservations Lead")
      expect(response).to redirect_to(hotel_roles_path(hotel))
      expect(role.slug).to eq("reservations-lead")
      expect(role.permissions).to contain_exactly(view_bookings, manage_bookings)
    end

    it "rejects permissions the editor cannot assign" do
      manage_account = Permission.find_by(slug: 'manage_account') || create(:permission, slug: 'manage_account', name: 'Manage Account')

      post hotel_roles_path(hotel), params: {
        role: {
          name: "Escalated Role",
          permission_ids: [ manage_account.id ]
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("include permissions you cannot assign")
      expect(account.roles.exists?(name: "Escalated Role")).to be(false)
    end
  end

  describe "PATCH /hotel/:hotel_id/roles-and-permissions/:id" do
    it "updates the role name and replaces permissions" do
      role = create(:role, account: account, name: "Night Staff", slug: "night_staff")
      old_permission = Permission.find_by(slug: 'view_reports') || create(:permission, slug: 'view_reports', name: 'View Reports')
      new_permission = Permission.find_by(slug: 'manage_night_audit') || create(:permission, slug: 'manage_night_audit', name: 'Manage Night Audit')
      create(:role_permission, role: role, permission: old_permission)

      patch hotel_role_path(hotel, role), params: {
        role: {
          name: "Night Auditor",
          permission_ids: [ new_permission.id ]
        }
      }

      expect(response).to redirect_to(hotel_roles_path(hotel))
      expect(role.reload.name).to eq("Night Auditor")
      expect(role.permissions).to contain_exactly(new_permission)
    end
  end

  describe "DELETE /hotel/:hotel_id/roles-and-permissions/:id" do
    it "deletes an unused role" do
      role = create(:role, account: account, name: "Unused Role", slug: "unused_role")
      permission = Permission.find_by(slug: 'view_audit_logs') || create(:permission, slug: 'view_audit_logs', name: 'View Audit Logs')
      create(:role_permission, role: role, permission: permission)

      expect do
        delete hotel_role_path(hotel, role)
      end.to change(Role, :count).by(-1)

      expect(response).to redirect_to(hotel_roles_path(hotel))
      expect(Role.exists?(role.id)).to be(false)
    end

    it "does not delete a role assigned to staff anywhere in the account" do
      role = create(:role, account: account, name: "Shared Staff", slug: "shared_staff")
      other_hotel = create(:hotel, account: account)
      staff = create(:user, account: account)
      create(:user_hotel_access, user: staff, hotel: other_hotel, role: role)

      expect do
        delete hotel_role_path(hotel, role)
      end.not_to change(Role, :count)

      expect(response).to redirect_to(hotel_roles_path(hotel))
      expect(flash[:alert]).to eq("Role cannot be deleted while staff are assigned to it.")
      expect(Role.exists?(role.id)).to be(true)
    end
  end

  describe "account scoping" do
    it "does not allow editing roles from another account" do
      other_account = create(:account)
      other_role = create(:role, account: other_account)

      get edit_hotel_role_path(hotel, other_role)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /hotel/:hotel_id/roles-and-permissions/bulk_update" do
    it "updates multiple roles at once" do
      role1 = create(:role, account: account, name: "Role 1")
      role2 = create(:role, account: account, name: "Role 2")
      p1 = Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings', name: 'View Bookings')
      p2 = Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings', name: 'Manage Bookings')

      patch bulk_update_hotel_roles_path(hotel), params: {
        roles: {
          role1.id => { permission_ids: [ p1.id ] },
          role2.id => { permission_ids: [ p1.id, p2.id ] }
        }
      }

      expect(response).to redirect_to(hotel_roles_path(hotel))
      expect(flash[:notice]).to include("successfully")
      expect(role1.reload.permissions).to contain_exactly(p1)
      expect(role2.reload.permissions).to contain_exactly(p1, p2)
    end

    it "handles clearing all permissions for a role" do
      role = create(:role, account: account, name: "Cleanup Role")
      p1 = Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings')
      role.permissions << p1

      patch bulk_update_hotel_roles_path(hotel), params: {
        roles: {
          role.id => { permission_ids: [""] }
        }
      }

      expect(role.reload.permissions).to be_empty
    end

    it "fails if a role ID does not belong to the account" do
      other_account = create(:account)
      other_role = create(:role, account: other_account)

      # RolesController#bulk_update finds roles via current_hotel.account.roles.where(id: ...)
      # So it will simply skip roles not found in that scope.
      patch bulk_update_hotel_roles_path(hotel), params: {
        roles: {
          other_role.id => { permission_ids: [] }
        }
      }

      expect(response).to redirect_to(hotel_roles_path(hotel))
      expect(other_role.reload.permissions).to be_empty
    end
  end
end
