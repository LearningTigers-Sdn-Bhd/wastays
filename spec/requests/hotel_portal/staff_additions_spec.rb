# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::StaffAdditions", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:manager) { create(:user, account: hotel.account) }
  let(:manager_role) { create(:role, account: hotel.account) }
  let(:staff_role) { create(:role, account: hotel.account, name: "Front Desk") }
  let(:headers) { { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "settings_action_sheet" } }
  let(:attributes) { { email: "new.staff@example.com", name: "New Staff", role_id: staff_role.id } }

  before do
    manager_role.permissions << (Permission.find_by(slug: "manage_users") || create(:permission, slug: "manage_users"))
    create(:user_hotel_access, user: manager, hotel: hotel, role: manager_role)
    sign_in_as(manager)
  end

  it "opens an email-first sheet in the settings frame" do
    get new_hotel_staff_addition_path(hotel), headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Staff", "Login email", "Continue", 'id="settings_action_sheet"')
    expect(response.body).not_to include("Full name", "Assigned role")
  end

  it "looks up without writes and shows the new-user fields" do
    counts = [ User.count, UserHotelAccess.count, StaffInvitation.count ]
    post lookup_hotel_staff_addition_path(hotel), params: { staff_addition: { email: attributes[:email] } }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Full name", "Assigned role", "temporary password", "Change email")
    expect([ User.count, UserHotelAccess.count, StaffInvitation.count ]).to eq(counts)
    expect(response.body).to include('target="settings_action_sheet"')
  end

  it "shows existing identity as read-only and never exposes credentials during lookup" do
    existing = create(:user, account: hotel.account, temporary_password: "password123", temporary_password_hotel: hotel)
    post lookup_hotel_staff_addition_path(hotel), params: { staff_addition: { email: existing.email } }, headers: headers

    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[name="staff_addition[name]"]')["value"]).to eq(existing.name)
    expect(doc.at_css('input[name="staff_addition[name]"]')["readonly"]).to be_present
    expect(doc.at_css('input[name="staff_addition[email]"]')["readonly"]).to be_present
    expect(response.body).to include("password will stay the same")
    expect(response.body).not_to include("password123")
  end

  it "warns before replacing an outstanding unsent or expired invitation" do
    create(:staff_invitation, :held, hotel: hotel, account: hotel.account, email: attributes[:email], expires_at: 1.day.ago)

    post lookup_hotel_staff_addition_path(hotel), params: { staff_addition: { email: attributes[:email] } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Adding this staff member will cancel their outstanding invitation.")
    expect(response.body).to include('id="settings_action_sheet"')
  end

  it "creates staff and shows non-cached credentials without sending mail" do
    expect {
      post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }, headers: headers
    }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

    staff = User.find_by!(email: attributes[:email])
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Temporary sign-in details", staff.temporary_password, 'target="settings_action_sheet"')
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(staff.active_user_hotel_accesses.find_by!(hotel: hotel).role).to eq(staff_role)
  end

  it "returns HTML credentials in a matching frame" do
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="settings_action_sheet"', "Temporary sign-in details")
  end

  it "links existing staff and ignores tampered identity and account parameters" do
    existing = create(:user, account: hotel.account, email: attributes[:email], password: "existing-password")
    original = existing.attributes
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes.merge(
      account_id: create(:account).id, user_id: manager.id, role: "superadmin", password: "tampered-password"
    ) }, headers: headers

    expect(response.body).to include('action="complete_sheet"', hotel_users_path(hotel))
    expect(response.body).not_to include("Temporary sign-in details", "existing-password")
    expect(existing.reload.attributes).to eq(original)
    expect(existing.user_hotel_accesses.find_by!(hotel: hotel).role).to eq(staff_role)
  end

  it "redirects to Staff Management after linking with HTML" do
    create(:user, account: hotel.account, email: attributes[:email])
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }

    expect(response).to redirect_to(hotel_users_path(hotel))
    expect(response).to have_http_status(:see_other)
  end

  it "preserves name, email and selected role after validation failure" do
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes.merge(name: "") }, headers: headers

    expect(response).to have_http_status(:unprocessable_content)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('input[name="staff_addition[email]"]')["value"]).to eq(attributes[:email])
    expect(doc.at_css('input[name="staff_addition[name]"]')["value"]).to eq("")
    expect(doc.at_css('select[name="staff_addition[role_id]"] option[selected]')["value"]).to eq(staff_role.id.to_s)
    expect(response.body).to include("Name")
  end

  it "preserves typed values when the selected role is rejected" do
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes.merge(role_id: create(:role).id) }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Selected role cannot be assigned", "New Staff")
    expect(User.exists?(email: attributes[:email])).to be(false)
  end

  it "rejects assignment of account-management roles without permission" do
    permission = Permission.find_by(slug: "manage_account") || create(:permission, slug: "manage_account")
    staff_role.permissions << permission
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.exists?(email: attributes[:email])).to be(false)
  end

  it "allows assignable account-management roles for an authorized account manager" do
    permission = Permission.find_by(slug: "manage_account") || create(:permission, slug: "manage_account")
    manager_role.permissions << permission
    manager.roles << manager_role
    staff_role.permissions << permission
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }

    expect(response).to have_http_status(:ok)
    expect(User.find_by!(email: attributes[:email]).user_hotel_accesses.find_by!(hotel: hotel).role).to eq(staff_role)
  end

  it "rechecks eligibility after lookup" do
    post lookup_hotel_staff_addition_path(hotel), params: { staff_addition: { email: attributes[:email] } }
    create(:user, :corporate, email: attributes[:email])

    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("This login cannot be added as staff")
    expect(User.find_by!(email: attributes[:email]).user_hotel_accesses).to be_empty
  end

  it "rejects invalid email and directs revoked staff to the existing restore action" do
    post lookup_hotel_staff_addition_path(hotel), params: { staff_addition: { email: "invalid" } }
    expect(response).to have_http_status(:unprocessable_content)

    staff = create(:user, account: hotel.account)
    create(:user_hotel_access, user: staff, hotel: hotel, role: staff_role, deactivated_at: 1.day.ago)
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes.merge(email: staff.email) }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Restore access through their existing staff row")
    expect(staff.user_hotel_accesses.find_by!(hotel: hotel)).not_to be_active
  end

  it "requires manage_users for opening, lookup, and creation" do
    manager_role.permissions.clear
    get new_hotel_staff_addition_path(hotel)
    expect(response).to have_http_status(:redirect)
    post lookup_hotel_staff_addition_path(hotel), params: { staff_addition: attributes }
    expect(response).to have_http_status(:redirect)
    expect {
      post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }
    }.not_to change(User, :count)
    expect(response).to have_http_status(:redirect)
  end

  it "preserves the onboarding review write restriction" do
    hotel.update!(status: "pending_review")
    post hotel_staff_addition_path(hotel), params: { staff_addition: attributes }

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
    expect(User.exists?(email: attributes[:email])).to be(false)
  end
end
