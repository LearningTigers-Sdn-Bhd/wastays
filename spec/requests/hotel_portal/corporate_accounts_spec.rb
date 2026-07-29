# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::CorporateAccounts", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:permission) { Permission.find_by(slug: "manage_corporate_accounts") || create(:permission, name: "Manage Corporate Accounts", slug: "manage_corporate_accounts") }

  before do
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "lists only relationships belonging to the current hotel" do
    visible = create(:hotel_corporate_account, hotel: hotel)
    hidden = create(:hotel_corporate_account)

    get hotel_corporate_accounts_path(hotel)
    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:success)
    expect(hotel_corporate_accounts_path(hotel)).to include("/accounts-receivable/corporate-accounts")
    expect(document.at_css("[data-testid='external-account-row-#{visible.id}']")).to be_present
    expect(document.at_css("[data-testid='external-account-row-#{hidden.id}']")).to be_nil
    expect(response.body).to include(visible.corporate_account.name)
    expect(response.body).not_to include(hidden.corporate_account.name)
  end

  it "renders invitations as pinned rows in the same table" do
    live = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user, expires_at: 3.days.from_now)
    lapsed = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user, expires_at: 2.days.ago)

    get hotel_corporate_accounts_path(hotel)
    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:success)
    expect(document.at_css("[data-testid='external-invitation-row-#{live.id}']").text).to include(live.email, "Pending")
    expect(document.at_css("[data-testid='external-invitation-row-#{lapsed.id}']").text).to include("Expired")

    # A live invitation offers resend + revoke; a lapsed one only resend.
    expect(document.at_css("[data-testid='external-invitation-actions-#{live.id}']")).to be_present
    expect(document.at_css("[data-testid='external-invitation-actions-#{lapsed.id}']")).to be_nil
  end

  it "counts both sources in the account type tabs" do
    create(:hotel_corporate_account, hotel: hotel, account_type: "company")
    create(:hotel_corporate_account, hotel: hotel, account_type: "government")
    create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user, account_type: "company")

    get hotel_corporate_accounts_path(hotel)
    tabs = Nokogiri::HTML(response.body).css("[data-slot='tabs-trigger']")

    expect(tabs.map { |tab| tab["data-tab-label"] }).to include("All", "Company", "Government", "Travel agent", "Airline")
    expect(tabs.find { |tab| tab["data-tab-label"] == "All" }.text).to include("3")
    expect(tabs.find { |tab| tab["data-tab-label"] == "Company" }.text).to include("2")
  end

  it "filters to lapsed invitations only for the expired status" do
    relationship = create(:hotel_corporate_account, hotel: hotel)
    lapsed = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user, expires_at: 2.days.ago)

    get hotel_corporate_accounts_path(hotel, status: "expired")
    document = Nokogiri::HTML(response.body)

    expect(document.at_css("[data-testid='external-invitation-row-#{lapsed.id}']")).to be_present
    expect(document.at_css("[data-testid='external-account-row-#{relationship.id}']")).to be_nil
  end

  it "reports open AR that the credit limit cannot be compared against" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: hotel, credit_limit: 1_000, credit_currency: "MYR")
    booking = create(:booking, hotel: hotel, currency: "USD")
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship, currency: "USD")
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 800, outstanding_amount: 800, currency: "USD")

    get hotel_corporate_accounts_path(hotel)
    row = Nokogiri::HTML(response.body).at_css("[data-testid='external-account-row-#{relationship.id}']").text

    # The comparable figure is MYR 0.00; the USD balance must not vanish with it.
    expect(row).to include("USD 800.00", "not comparable with the MYR limit")
  end

  it "shows warning-only credit exposure for near-limit accounts" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: hotel, credit_limit: 100)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 90, outstanding_amount: 90)

    get hotel_corporate_accounts_path(hotel)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Projected AR exposure MYR 90.00 is 90% of credit limit MYR 100.00")
    expect(response.body).to include("Direct Bill is still allowed")
  end

  it "renders the invitation form in the offcanvas frame" do
    get new_hotel_corporate_account_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
    expect(response.body).to include("Invite External Account")
    expect(response.body).to include("Corporate contact email")
    expect(response.body).not_to include("Company name")
  end

  it "creates a corporate invitation and completes the offcanvas" do
    expect {
      post hotel_corporate_accounts_path(hotel), params: {
        corporate_invitation: {
          email: "billing@acme.test",
          relationship_type: "standard",
          credit_currency: "MYR"
        }
      }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }
    }.to change(CorporateInvitation, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_offcanvas"')
    expect(response.body).to include(hotel_corporate_accounts_path(hotel))
    expect(CorporateInvitation.last.metadata).to include(
      "relationship_type" => "standard",
      "credit_currency" => "MYR"
    )
  end

  it "keeps service errors and submitted values inside the offcanvas" do
    create(:user, email: "staff@example.com")

    post hotel_corporate_accounts_path(hotel), params: {
        corporate_invitation: {
          email: "staff@example.com",
          relationship_type: "direct_bill",
        credit_currency: "MYR"
      }
    }, headers: { "Turbo-Frame" => "offcanvas_drawer" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("hotel staff")
    expect(response.body).to include("staff@example.com")
    expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
  end

  it "cannot suspend another hotel's relationship" do
    relationship = create(:hotel_corporate_account)

    patch suspend_hotel_corporate_account_path(hotel, relationship)

    expect(response).to have_http_status(:not_found)
    expect(relationship.reload).to be_active
  end

  it "resends an expired unaccepted invitation with a new token" do
    invitation = create(
      :corporate_invitation,
      hotel: hotel,
      account: account,
      invited_by_user: user,
      expires_at: 1.minute.ago
    )
    old_digest = invitation.token_digest

    post resend_hotel_corporate_invitation_path(hotel, invitation)

    expect(response).to redirect_to(hotel_corporate_accounts_path(hotel))
    expect(invitation.reload.token_digest).not_to eq(old_digest)
    expect(invitation).to be_pending
  end

  it "revokes an unaccepted invitation" do
    invitation = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user)

    expect {
      delete hotel_corporate_invitation_path(hotel, invitation)
    }.to change(CorporateInvitation, :count).by(-1)
  end

  it "re-renders the results frame with the active filters after revoking" do
    kept = create(:hotel_corporate_account, hotel: hotel, account_type: "government")
    filtered_out = create(:hotel_corporate_account, hotel: hotel, account_type: "company")
    invitation = create(:corporate_invitation, hotel: hotel, account: account, invited_by_user: user)

    delete hotel_corporate_invitation_path(hotel, invitation, account_type: "government"),
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('target="corporate_accounts_results"')
    expect(response.body).to include("external-account-row-#{kept.id}")
    expect(response.body).not_to include("external-account-row-#{filtered_out.id}")
  end

  it "does not expose the legacy corporate accounts path" do
    get "/hotel/#{hotel.slug}/corporate-accounts"

    expect(response).to have_http_status(:not_found)
  end
end
