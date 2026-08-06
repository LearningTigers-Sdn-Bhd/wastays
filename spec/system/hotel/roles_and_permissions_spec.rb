# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel roles and permissions", type: :system, js: true do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan) }
  let(:user) { create(:user, account: account, name: "Dana Operator") }
  let(:owner_role) { create(:role, account: account, name: "Hotel Owner", slug: "hotel_owner") }
  let!(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }

  let(:manage_users) do
    Permission.find_or_create_by!(slug: "manage_users") { |record| record.name = "Manage Users" }
  end
  let!(:view_bookings) do
    Permission.find_or_create_by!(slug: "view_bookings") { |record| record.name = "View Bookings" }
  end
  let!(:manage_rates) do
    Permission.find_or_create_by!(slug: "manage_rates") { |record| record.name = "Manage Rates" }
  end

  before do
    driven_by(:cuprite)
    owner_role.permissions << manage_users
    create(:user_hotel_access, user: user, hotel: hotel, role: owner_role)
    create(:plan_feature,
           plan: plan,
           feature: create(:feature, feature_group: feature_group, slug: "role_based_access_control"),
           enabled: true)
    sign_in_through_ui(user)
  end

  it "reads as a matrix of granted permissions with no controls until editing" do
    staff_role.permissions << view_bookings

    visit hotel_roles_path(hotel)

    expect(page).to have_content("Roles & Permissions")
    within("[data-testid='permission-matrix']") do
      expect(page).to have_content("Front Desk")
      expect(page).to have_content("View Bookings")
      # State is spelled out, not left to the colour of an icon.
      expect(page).to have_content("Granted")
      expect(page).to have_content("Not granted")
      expect(page).to have_no_field("View Bookings for Front Desk")
    end

    expect(page).to have_button("Edit Permissions")
    expect(page).to have_no_button("Save Permissions")
  end

  it "swaps the header actions for the editing pair and back again" do
    visit hotel_roles_path(hotel)

    click_button "Edit Permissions"

    expect(page).to have_button("Save Permissions")
    expect(page).to have_button("Cancel")
    expect(page).to have_no_button("Edit Permissions")
    expect(page).to have_no_link("New Role")
    expect(page).to have_field("View Bookings for Front Desk")

    click_button "Cancel"

    expect(page).to have_button("Edit Permissions")
    expect(page).to have_no_button("Save Permissions")
    expect(page).to have_no_field("View Bookings for Front Desk")
  end

  it "grants a permission across the matrix and saves it" do
    visit hotel_roles_path(hotel)

    click_button "Edit Permissions"
    check "View Bookings for Front Desk"
    click_button "Save Permissions"

    expect(page).to have_content("Permissions updated successfully", wait: 5)
    expect(staff_role.reload.permissions).to include(view_bookings)
  end

  it "discards the ticks it was holding when editing is cancelled" do
    staff_role.permissions << view_bookings

    visit hotel_roles_path(hotel)

    click_button "Edit Permissions"
    uncheck "View Bookings for Front Desk"
    check "Manage Rates for Front Desk"
    click_button "Cancel"

    # Re-entering must show the saved state, not the abandoned edits: the icons
    # behind the boxes never moved, so leaving the boxes changed contradicts them.
    click_button "Edit Permissions"
    expect(page).to have_field("View Bookings for Front Desk", checked: true)
    expect(page).to have_field("Manage Rates for Front Desk", checked: false)
    expect(staff_role.reload.permissions).to contain_exactly(view_bookings)
  end

  it "filters the matrix to matching permissions and says when none match" do
    visit hotel_roles_path(hotel)

    fill_in "Search permissions", with: "rates"

    expect(page).to have_content("Manage Rates")
    expect(page).to have_no_content("View Bookings")

    fill_in "Search permissions", with: "nothing at all"

    expect(page).to have_content("No permissions match that search")
  end

  it "creates a role through the sheet" do
    visit hotel_roles_path(hotel)

    click_link "New Role"

    expect(page).to have_css("dialog#new-role-sheet[open]")
    within("dialog#new-role-sheet") do
      fill_in "Role Name", with: "Night Manager"
      click_button "Create Role"
    end

    expect(page).to have_no_css("dialog#new-role-sheet", wait: 5)
    expect(page).to have_content("Night Manager")
    expect(account.roles.find_by(name: "Night Manager").slug).to eq("night-manager")
  end

  it "renames a role from its column menu" do
    visit hotel_roles_path(hotel)

    find("#role-#{staff_role.id}-actions-trigger").click
    click_link "Edit role"

    expect(page).to have_css("dialog#edit-role-sheet[open]")
    within("dialog#edit-role-sheet") do
      fill_in "Role Name", with: "Reception"
      click_button "Save Changes"
    end

    expect(page).to have_no_css("dialog#edit-role-sheet", wait: 5)
    expect(staff_role.reload.name).to eq("Reception")
  end

  it "deletes an unassigned role and refuses to offer it for an assigned one" do
    visit hotel_roles_path(hotel)

    # Your own role is in use, so the menu does not offer to delete it.
    find("#role-#{owner_role.id}-actions-trigger").click
    expect(page).to have_link("Edit role")
    expect(page).to have_no_link("Delete role")
    find("body").send_keys(:escape)

    find("#role-#{staff_role.id}-actions-trigger").click
    click_link "Delete role"

    # The confirm dialog is modal above the menu, so Capybara cannot see it.
    expect(page).to have_css("dialog#turbo-confirm-dialog", visible: :all)
    click_in_overlay find("#turbo-confirm-button", visible: :all)

    expect(page).to have_no_content("Front Desk", wait: 5)
    expect(Role.exists?(staff_role.id)).to be false
  end
end
