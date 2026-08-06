# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel staff management", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account, name: "Dana Operator") }
  let(:owner_role) { create(:role, account: account, name: "Hotel Owner", slug: "hotel_owner") }
  let(:staff_role) { create(:role, account: account, name: "Front Desk", slug: "front_desk") }
  let(:manager_role) { create(:role, account: account, name: "Duty Manager", slug: "duty_manager") }

  let(:manage_users) do
    Permission.find_or_create_by!(slug: "manage_users") { |record| record.name = "Manage Users" }
  end
  let(:manage_account) do
    Permission.find_or_create_by!(slug: "manage_account") { |record| record.name = "Manage Account" }
  end

  let(:colleague) { create(:user, account: account, name: "Aisha Rahman", email: "aisha@example.com") }
  let!(:colleague_access) { create(:user_hotel_access, user: colleague, hotel: hotel, role: staff_role) }

  before do
    driven_by(:cuprite)
    owner_role.permissions << manage_users
    create(:user_hotel_access, user: user, hotel: hotel, role: owner_role)
    manager_role # referenced by the role picker
    sign_in_through_ui(user)
  end

  it "lists staff with status and role as plain text, with no inline select" do
    visit hotel_users_path(hotel)

    expect(page).to have_content("Staff Management")

    within("[data-testid='staff-directory']") do
      expect(page).to have_content("Aisha Rahman")
      expect(page).to have_content("aisha@example.com")
      expect(page).to have_content("Front Desk")
      expect(page).to have_content("Active")
      # Role is read-only on the listing; editing happens in the sheet.
      expect(page).to have_no_css("select", visible: :all)
    end

    # Your own row offers nothing actionable.
    expect(page).to have_content("You")
  end

  it "changes a role through the edit sheet" do
    visit hotel_users_path(hotel)

    find("#staff-#{colleague_access.id}-actions-trigger").click
    click_link "Edit access"

    expect(page).to have_css("dialog#edit-staff-access-sheet[open]")
    within("dialog#edit-staff-access-sheet") do
      expect(page).to have_content("Aisha Rahman")
      click_in_overlay find("#user_hotel_access_role_id-trigger")
      click_in_overlay find("[role='option']", text: "Duty Manager", visible: true)
      click_button "Save Changes"
    end

    expect(page).to have_no_css("dialog#edit-staff-access-sheet", wait: 5)
    expect(colleague_access.reload.role).to eq(manager_role)
    expect(page).to have_content("Duty Manager")
  end

  it "revokes and restores access with the status switch in the table" do
    visit hotel_users_path(hotel)

    within("#staff-row-#{colleague_access.id}") do
      expect(page).to have_content("Active")
      uncheck "Access for Aisha Rahman"
    end

    # Revoking is confirmed; the dialog is modal so Capybara cannot see it.
    expect(page).to have_css("dialog#turbo-confirm-dialog", visible: :all)
    click_in_overlay find("#turbo-confirm-button", visible: :all)

    expect(page).to have_content("Aisha Rahman's access was revoked", wait: 5)
    expect(colleague_access.reload.deactivated_at).not_to be_nil
    within("#staff-row-#{colleague_access.id}") { expect(page).to have_content("Revoked") }

    # Restoring is not destructive, so it applies without a confirm.
    within("#staff-row-#{colleague_access.id}") { check "Access for Aisha Rahman" }

    expect(page).to have_content("Aisha Rahman's access was restored", wait: 5)
    expect(colleague_access.reload.deactivated_at).to be_nil
  end

  it "puts the status switch back when the confirm is cancelled" do
    visit hotel_users_path(hotel)

    within("#staff-row-#{colleague_access.id}") { uncheck "Access for Aisha Rahman" }

    expect(page).to have_css("dialog#turbo-confirm-dialog", visible: :all)
    click_in_overlay find("[data-slot='alert-dialog-cancel']", visible: :all)

    # Nothing was submitted, so the control must return to the saved state
    # rather than sitting on a change that never happened.
    within("#staff-row-#{colleague_access.id}") do
      expect(page).to have_field("Access for Aisha Rahman", checked: true)
      expect(page).to have_content("Active")
    end
    expect(colleague_access.reload.deactivated_at).to be_nil
  end

  it "locks the status switch on your own row" do
    visit hotel_users_path(hotel)

    my_access = UserHotelAccess.find_by(user: user, hotel: hotel)
    within("#staff-row-#{my_access.id}") do
      expect(page).to have_field("Access for Dana Operator — You cannot revoke your own access.", disabled: true)
    end
  end

  it "hides permanent deletion from a manager without account management" do
    visit hotel_users_path(hotel)

    find("#staff-#{colleague_access.id}-actions-trigger").click

    expect(page).to have_link("Edit access")
    expect(page).to have_no_button("Delete permanently")
  end

  it "permanently deletes an access once account management is held" do
    owner_role.permissions << manage_account

    visit hotel_users_path(hotel)
    find("#staff-#{colleague_access.id}-actions-trigger").click
    click_button "Delete permanently"

    # The confirm dialog is modal above the menu, so Capybara cannot see it.
    expect(page).to have_css("dialog#turbo-confirm-dialog", visible: :all)
    click_in_overlay find("#turbo-confirm-button", visible: :all)

    expect(page).to have_no_content("Aisha Rahman", wait: 5)
    expect(UserHotelAccess.exists?(colleague_access.id)).to be false
    expect(User.exists?(colleague.id)).to be true
  end

  it "invites a staff member through the sheet" do
    visit hotel_users_path(hotel)

    click_link "Invite Staff"

    expect(page).to have_css("dialog#invite-staff-sheet[open]")
    within("dialog#invite-staff-sheet") do
      fill_in "Email Address", with: "newhire@example.com"
      click_in_overlay find("#staff_invitation_role_id-trigger")
      click_in_overlay find("[role='option']", text: "Front Desk", visible: true)
      click_button "Send Invitation"
    end

    expect(page).to have_no_css("dialog#invite-staff-sheet", wait: 5)
    expect(page).to have_content("newhire@example.com")
    expect(StaffInvitation.find_by!(email: "newhire@example.com").role).to eq(staff_role)
  end
end
