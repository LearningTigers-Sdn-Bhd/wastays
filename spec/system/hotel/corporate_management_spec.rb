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

  it "opens, validates, cancels, and completes invitations in the offcanvas" do
    create(:user, email: "staff@example.com")
    visit hotel_corporate_accounts_path(hotel)

    expect(page).to have_content("External Accounts")
    expect(page).to have_link("External Accounts")

    click_link "Invite"
    expect(page).to have_css("turbo-frame#offcanvas_drawer", text: "Invite External Account")
    expect(page).to have_no_field("Company name")

    within("#offcanvas_drawer") do
      cancel_button = find("button[type='button']", text: "Cancel", exact_text: true)
      execute_script("arguments[0].click()", cancel_button)
    end
    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 2)

    click_link "Invite"
    within("#offcanvas_drawer") do
      fill_in "Corporate contact email", with: "staff@example.com"
      select "Direct bill", from: "Relationship"
      click_button "Send invitation"
    end

    within("#offcanvas_drawer") do
      expect(page).to have_content("hotel staff")
      expect(page).to have_field("Corporate contact email", with: "staff@example.com")

      fill_in "Corporate contact email", with: "billing@example.com"
      click_button "Send invitation"
    end

    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 3)
    expect(page).to have_content("billing@example.com")
    expect(CorporateInvitation.find_by!(email: "billing@example.com").relationship_type).to eq("direct_bill")
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
