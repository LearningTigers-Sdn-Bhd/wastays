# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel corporate management", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
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

  # Credit currency, credit limit and payment terms describe how an account is
  # invoiced. A standard account settles at checkout and is never invoiced, so
  # the three fields ask a question that does not apply to it.
  it "shows the billing terms only once the relationship is direct bill" do
    visit hotel_corporate_accounts_path(hotel)
    click_button "Add / Invite"
    click_link "Invite account"
    expect(page).to have_css("dialog#external-account-sheet[open]")

    within("dialog#external-account-sheet") do
      expect(page).to have_checked_field("Direct bill — Invoice the company")
      expect(page).to have_field("Credit limit")
      expect(page).to have_field("Payment terms (days)")
      expect(page).to have_content("Credit currency")

      choose "Standard — Settle by checkout"

      expect(page).to have_no_field("Credit limit")
      expect(page).to have_no_field("Payment terms (days)")
    end
  end

  it "opens, validates, cancels, and completes invitations in the sheet" do
    create(:user, email: "staff@example.com")
    visit hotel_corporate_accounts_path(hotel)

    expect(page).to have_content("External Accounts")
    expect(page).to have_link("External Accounts")

    click_button "Add / Invite"
    click_link "Invite account"
    expect(page).to have_css("turbo-frame#external_account_sheet dialog#external-account-sheet[open]")
    expect(page).to have_no_field("Company name")

    within("dialog#external-account-sheet") { click_in_overlay "Cancel" }
    expect(page).to have_no_css("dialog#external-account-sheet", wait: 5)

    click_button "Add / Invite"
    click_link "Invite account"
    within("dialog#external-account-sheet") do
      fill_in "Corporate contact email", with: "staff@example.com"
      click_in_overlay "Send invitation"
    end

    # The service rejects a staff address; the sheet must stay open with the
    # value intact so it can be corrected in place.
    within("dialog#external-account-sheet") do
      expect(page).to have_content("hotel staff")
      expect(page).to have_field("Corporate contact email", with: "staff@example.com")

      fill_in "Corporate contact email", with: "billing@example.com"
      click_in_overlay "Send invitation"
    end

    expect(page).to have_no_css("dialog#external-account-sheet", wait: 5)
    expect(page).to have_content("billing@example.com")
    expect(CorporateInvitation.find_by!(email: "billing@example.com").relationship_type).to eq("direct_bill")
  end

  it "opens an account from its row and saves billing in the workspace" do
    relationship = create(:hotel_corporate_account, hotel: hotel, account_type: "government",
      relationship_type: "direct_bill", payment_terms_days: 14)
    visit hotel_corporate_accounts_path(hotel, account_type: "government")
    find("[data-testid='external-account-row-#{relationship.id}']").click

    expect(page).to have_css("[data-testid='corporate-account-workspace']")
    expect(page).to have_no_css("dialog#external-account-sheet")
    fill_in "Payment terms (days)", with: "45"
    click_button "Save changes"
    expect(page).to have_field("Payment terms (days)", with: "45")
    expect(relationship.reload.payment_terms_days).to eq(45)
    click_link "Back to accounts"
    expect(page).to have_current_path(hotel_corporate_accounts_path(hotel, account_type: "government"), ignore_query: false)
  end

  it "suspends an account from the workspace More menu" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    visit hotel_corporate_accounts_path(hotel)
    within("[data-testid='external-account-row-#{relationship.id}']") { click_button "More" }
    click_link "Edit"
    expect(page).to have_css("[data-testid='corporate-account-workspace']")
    within("turbo-frame#corporate_account_workspace") { click_button "More" }
    click_button "Suspend account"
    expect(page).to have_css("dialog#turbo-confirm-dialog[open]")
    click_in_overlay find("#turbo-confirm-button", visible: :all)
    expect(page).to have_content("Suspended")
    expect(relationship.reload).to be_suspended
    expect(page).to have_css("[data-testid='corporate-account-workspace']")
  end

  it "saves company details and billing address through separate workspace tabs" do
    corporate_user = create(:user, :corporate)
    relationship = create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account)
    visit edit_hotel_corporate_account_path(hotel, relationship)
    click_link "Company details"
    fill_in "Company name", with: "Updated Agency"
    fill_in "Contact person", with: "Updated Contact"
    click_button "Save changes"
    expect(page).to have_field("Company name", with: "Updated Agency")
    expect(page).to have_css("h1", text: "Updated Agency")
    click_link "Billing address"
    fill_in "Address line 1", with: "12 Jalan Lintas"
    fill_in "City", with: "Kota Kinabalu"
    click_button "Save changes"
    expect(page).to have_field("City", with: "Kota Kinabalu")
    expect(relationship.reload.billing_city).to eq("Kota Kinabalu")
    click_link "Manage billing"
    expect(page).to have_checked_field("Standard — Settle by checkout")
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

  it "creates an account from the Add sheet and reveals its temporary credentials only on request" do
    visit hotel_corporate_accounts_path(hotel)
    click_button "Add / Invite"
    click_link "Add account"
    within("dialog#external-account-add-sheet") do
      fill_in "Login email", with: "added@example.com"
      click_in_overlay "Continue"
    end
    within("dialog#external-account-add-sheet") do
      expect(page).to have_checked_field("Direct bill — Invoice the company")
      fill_in "Company name", with: "Added Agency"
      fill_in "Contact person", with: "Agent Contact"
      click_in_overlay "Add account"
    end
    expect(page).to have_css("dialog#external-account-credentials[open]")
    within("dialog#external-account-credentials") do
      message = find_field("Message to send")
      expect(message.value).to include("added@example.com", "1. Open", "2. Sign in", "3. Open Profile")
      page.execute_script(<<~JS)
        Object.defineProperty(navigator, "clipboard", {
          configurable: true,
          value: { writeText(text) { window.copiedAccountAccessMessage = text; return Promise.resolve(); } }
        });
      JS
      click_in_overlay "Copy message"
      expect(page).to have_button("Copied")
      expect(page.evaluate_script("window.copiedAccountAccessMessage")).to eq(message.value)
      click_in_overlay "Done"
    end
    corporate_user = User.find_by!(email: "added@example.com")
    expect(page).to have_content("Added Agency")
    expect(page).to have_no_content(corporate_user.temporary_password)
    relationship = hotel.hotel_corporate_accounts.find_by!(corporate_account: corporate_user.account)
    within("[data-testid='external-account-row-#{relationship.id}']") { click_button "More" }
    click_link "Show temporary password"
    within("dialog#external-account-credentials") do
      expect(find_field("Message to send").value).to include(corporate_user.temporary_password)
    end
  end

  it "links an existing account without changing its profile or password" do
    corporate_user = create(:user, :corporate)
    original_digest = corporate_user.password_digest
    visit hotel_corporate_accounts_path(hotel)
    click_button "Add / Invite"
    click_link "Add account"
    within("dialog#external-account-add-sheet") do
      fill_in "Login email", with: corporate_user.email
      click_in_overlay "Continue"
    end
    within("dialog#external-account-add-sheet") do
      expect(page).to have_content(corporate_user.account.name)
      expect(page).to have_no_field("Company name")
      click_in_overlay "Add account"
    end
    expect(page).to have_no_css("dialog#external-account-add-sheet")
    expect(page).to have_content(corporate_user.account.name)
    expect(corporate_user.reload.password_digest).to eq(original_digest)
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
