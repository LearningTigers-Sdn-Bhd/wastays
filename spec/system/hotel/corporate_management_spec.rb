# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel corporate management", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:permission) do
    Permission.find_or_create_by!(slug: "manage_corporate_accounts") do |record|
      record.name = "Manage Corporate Accounts"
    end
  end

  before do
    driven_by(:cuprite)
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_through_ui(user)
  end

  it "opens, validates, cancels, and completes invitations in the sheet" do
    create(:user, email: "staff@example.com")
    visit hotel_corporate_accounts_path(hotel)

    expect(page).to have_content("External Accounts")
    expect(page).to have_link("External Accounts")

    click_link "Invite"
    expect(page).to have_css("turbo-frame#external_account_sheet dialog#external-account-sheet[open]")
    expect(page).to have_no_field("Company name")

    within("dialog#external-account-sheet") { click_button "Cancel" }
    expect(page).to have_no_css("dialog#external-account-sheet", wait: 5)

    click_link "Invite"
    within("dialog#external-account-sheet") do
      fill_in "Corporate contact email", with: "staff@example.com"
      click_in_overlay find("#corporate_invitation_relationship_type-trigger")
      click_in_overlay find("[role='option']", text: "Direct bill", visible: true)
      click_button "Send invitation"
    end

    # The service rejects a staff address; the sheet must stay open with the
    # value intact so it can be corrected in place.
    within("dialog#external-account-sheet") do
      expect(page).to have_content("hotel staff")
      expect(page).to have_field("Corporate contact email", with: "staff@example.com")

      fill_in "Corporate contact email", with: "billing@example.com"
      click_button "Send invitation"
    end

    expect(page).to have_no_css("dialog#external-account-sheet", wait: 5)
    expect(page).to have_content("billing@example.com")
    expect(CorporateInvitation.find_by!(email: "billing@example.com").relationship_type).to eq("direct_bill")
  end

  it "edits an account through the sheet and returns to the filtered index" do
    relationship = create(:hotel_corporate_account, hotel: hotel, account_type: "government", payment_terms_days: 14)

    visit hotel_corporate_accounts_path(hotel, account_type: "government")
    find("[data-testid='external-account-edit-#{relationship.id}']").click

    expect(page).to have_css("dialog#external-account-sheet[open]")
    within("dialog#external-account-sheet") do
      fill_in "Payment terms (days)", with: "45"
      click_button "Save changes"
    end

    expect(page).to have_no_css("dialog#external-account-sheet", wait: 5)
    expect(relationship.reload.payment_terms_days).to eq(45)
    # complete_sheet hard-navigates, so the filter has to survive in the destination.
    expect(page).to have_current_path(hotel_corporate_accounts_path(hotel, account_type: "government"), ignore_query: false)
  end

  it "suspends an account from the sheet footer" do
    relationship = create(:hotel_corporate_account, hotel: hotel)

    visit hotel_corporate_accounts_path(hotel)
    find("[data-testid='external-account-edit-#{relationship.id}']").click

    expect(page).to have_css("dialog#external-account-sheet[open]")
    find("[data-testid='external-account-suspend-#{relationship.id}']").click

    # The confirm dialog stacks above the already-modal sheet, so Capybara's
    # visibility check cannot see it — drive it through the overlay helper.
    expect(page).to have_css("dialog#turbo-confirm-dialog", visible: :all)
    click_in_overlay find("#turbo-confirm-button", visible: :all)

    expect(page).to have_no_css("dialog#external-account-sheet", wait: 5)
    expect(relationship.reload).to be_suspended
  end

  it "lists invitations and accounts in one table and narrows both by search" do
    strata = create(:hotel_corporate_account, hotel: hotel, account_type: "company",
      corporate_account: create(:account, :corporate, name: "Strata Professional"))
    northstar = create(:hotel_corporate_account, hotel: hotel, account_type: "company",
      corporate_account: create(:account, :corporate, name: "Northstar Holdings"))
    invitation = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user,
      email: "strata-travel@example.com", account_type: "travel_agent", expires_at: 3.days.from_now)

    visit hotel_corporate_accounts_path(hotel)

    expect(page).to have_css("[data-testid='external-invitation-row-#{invitation.id}']")
    expect(page).to have_css("[data-testid='external-account-row-#{strata.id}']")
    expect(page).to have_css("[data-testid='external-account-row-#{northstar.id}']")

    expect(find("[data-tab-label='All']")).to have_content("3")
    expect(find("[data-tab-label='Company']")).to have_content("2")

    find("input[name='query']").set("strata")

    # The search reaches both sources, and the tab counts follow it.
    expect(page).to have_no_css("[data-testid='external-account-row-#{northstar.id}']", wait: 5)
    expect(page).to have_css("[data-testid='external-account-row-#{strata.id}']")
    expect(page).to have_css("[data-testid='external-invitation-row-#{invitation.id}']")
    expect(find("[data-tab-label='All']")).to have_content("2")
    expect(find("[data-tab-label='Company']")).to have_content("1")
  end

  it "filters to a single account type from the tabs" do
    company = create(:hotel_corporate_account, hotel: hotel, account_type: "company")
    agent = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")

    visit hotel_corporate_accounts_path(hotel)
    find("[data-tab-label='Travel agent']").click

    expect(page).to have_css("[data-testid='external-account-row-#{agent.id}']")
    expect(page).to have_no_css("[data-testid='external-account-row-#{company.id}']")
  end

  it "surfaces a lapsed invitation as expired with resend as its only action" do
    lapsed = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user, expires_at: 2.days.ago)
    old_digest = lapsed.token_digest

    visit hotel_corporate_accounts_path(hotel)

    row = find("[data-testid='external-invitation-row-#{lapsed.id}']")
    expect(row).to have_content("Expired")
    expect(row).to have_css("[data-testid='external-invitation-resend-#{lapsed.id}']")
    expect(row).to have_no_css("[data-testid='external-invitation-revoke-#{lapsed.id}']")

    find("[data-testid='external-invitation-resend-#{lapsed.id}']").click

    # Reviving it turns the row back into a live invitation with both actions.
    expect(page).to have_css("[data-testid='external-invitation-revoke-#{lapsed.id}']", wait: 5)
    expect(lapsed.reload.token_digest).not_to eq(old_digest)
    expect(lapsed).to be_pending
  end

  it "keeps the active filter when revoking an invitation" do
    kept = create(:hotel_corporate_account, hotel: hotel, account_type: "government")
    other = create(:hotel_corporate_account, hotel: hotel, account_type: "company")
    invitation = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user,
      account_type: "government", expires_at: 3.days.from_now)

    visit hotel_corporate_accounts_path(hotel, account_type: "government")
    expect(page).to have_css("[data-testid='external-invitation-row-#{invitation.id}']")

    # Turbo's confirm is replaced by the PanelsUI alert dialog, so there is no
    # native confirm for accept_confirm to drive.
    find("[data-testid='external-invitation-revoke-#{invitation.id}']").click
    expect(page).to have_css("dialog#turbo-confirm-dialog[open]")
    within("dialog#turbo-confirm-dialog") { click_button "Confirm" }

    expect(page).to have_no_css("[data-testid='external-invitation-row-#{invitation.id}']", wait: 5)
    expect(page).to have_css("[data-testid='external-account-row-#{kept.id}']")
    expect(page).to have_no_css("[data-testid='external-account-row-#{other.id}']")
  end
end
