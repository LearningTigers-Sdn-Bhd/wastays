require "rails_helper"

RSpec.describe "Admin hotel workspace", type: :request do
  let(:admin_account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }
  let(:account) { create(:account, name: "Original account") }
  let(:hotel) { create(:hotel, account:, name: "Original hotel") }
  let(:owner_role) { create(:role, account:, slug: "hotel_owner") }
  let(:owner) { create(:user, :admin, account:, name: "First owner") }

  before do
    create(:user_hotel_access, user: owner, hotel:, role: owner_role)
    sign_in_as(superadmin)
  end

  it "shows active rooms in inventory and an empty banking state" do
    room_type = create(:room_type, hotel:, name: "Garden Room")
    create(:room, hotel:, room_type:, number: "G101")
    create(:room, hotel:, room_type:, number: "G102", archived_at: Time.current)

    get admin_hotel_path(hotel, tab: "room_inventory")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Garden Room", "G101")
    expect(response.body).not_to include("G102")

    get admin_hotel_path(hotel, tab: "banking_details")
    expect(response.body).to include("No banking details have been submitted yet")
  end

  it "shows an empty inventory and the salesperson form" do
    get admin_hotel_path(hotel, tab: "room_inventory")
    expect(response.body).to include("No room types have been added")

    get admin_hotel_path(hotel, tab: "salesperson")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create new salesperson", "Save assignment")
    expect(Nokogiri::HTML(response.body).at_css("#admin-hotel-tabs-tab-salesperson")["aria-current"]).to eq("page")
  end

  it "shows channel status and room mapping coverage in its tab" do
    room_type = create(:room_type, hotel:, name: "Garden Room")
    create(:channel_mapping, mappable: hotel, external_id: "hotel-42")
    create(:channel_mapping, mappable: room_type, external_id: "room-42")

    get admin_hotel_path(hotel, tab: "channel_manager")
    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("#admin-hotel-tabs-tab-channel_manager")["aria-current"]).to eq("page")
    expect(document.at_css("[data-testid='admin-hotel-tab-content']").parent["class"]).to include("px-5", "py-4")
    expect(response.body).to include("Connected", "hotel-42", "1 of 1", "Save preference", "Disconnect channel manager")
    expect(document.at_css("#admin-hotel-actions-menu").text).not_to include("Disconnect channel manager")
    expect(response.body).not_to include("Channel connection")
  end

  it "saves the channel preference and returns to its tab" do
    patch admin_hotel_path(hotel), params: { tab: "channel_manager", hotel: { preferred_channel_manager: "none" } }
    expect(response).to redirect_to(admin_hotel_path(hotel, tab: "channel_manager"))
    expect(hotel.reload.preferred_channel_manager).to eq("none")
  end

  it "returns to the channel tab after disconnecting" do
    create(:channel_mapping, mappable: hotel)

    post disconnect_channex_admin_hotel_path(hotel)
    expect(response).to redirect_to(admin_hotel_path(hotel, tab: "channel_manager"))
    expect(hotel.reload.channel_mapping).to be_nil
  end

  it "requires owner selection when several active owners exist" do
    second = create(:user, :admin, account:, name: "Second owner")
    create(:user_hotel_access, user: second, hotel:, role: owner_role)

    get admin_hotel_path(hotel, tab: "account_information")
    expect(response.body).to include("View owner")
    expect(response.body).not_to include("Send password reset link")

    get admin_hotel_path(hotel, tab: "account_information", owner_id: second.id)
    expect(response.body).to include("Send password reset link", second.email)
  end

  it "shows a pending owner invitation without password controls" do
    owner.user_hotel_accesses.destroy_all
    create(:staff_invitation, account:, hotel:, role: owner_role, invited_by_user: superadmin,
                              email: "pending-owner@example.com")

    get admin_hotel_path(hotel, tab: "account_information")
    expect(response.body).to include("Pending owner invitation: pending-owner@example.com")
    expect(response.body).not_to include("Send password reset link")
  end

  it "saves account and owner details together" do
    patch update_account_admin_hotel_path(hotel), params: {
      owner_id: owner.id, account: { name: "New account" }, owner: { name: "New owner", email: "new-owner@example.com" }
    }
    expect(response).to redirect_to(admin_hotel_path(hotel, tab: "account_information"))
    expect(account.reload.name).to eq("New account")
    expect(owner.reload).to have_attributes(name: "New owner", email: "new-owner@example.com")
  end

  it "rolls back account changes when the owner email is invalid" do
    patch update_account_admin_hotel_path(hotel), params: {
      owner_id: owner.id, account: { name: "Changed account" }, owner: { name: "First owner", email: "invalid" }
    }
    expect(account.reload.name).to eq("Original account")
    expect(response).to redirect_to(admin_hotel_path(hotel, tab: "account_information"))
  end

  it "rejects a user without active hotel owner access" do
    outsider = create(:user, :admin, account:)
    post send_owner_password_reset_admin_hotel_path(hotel), params: { owner_id: outsider.id }
    expect(response).to have_http_status(:not_found)
  end

  it "assigns and edits a salesperson without changing hotel details" do
    person = create(:user, account: admin_account, role: "salesperson", name: "Old seller")
    patch update_salesperson_admin_hotel_path(hotel), params: { salesperson: { operation: "assign", id: person.id } }
    expect(hotel.reload.salesperson).to eq(person)
    expect(person.reload.name).to eq("Old seller")

    patch update_salesperson_admin_hotel_path(hotel), params: { salesperson: { operation: "update_contact", name: "New seller", email: "seller@example.com" } }
    expect(person.reload).to have_attributes(name: "New seller", email: "seller@example.com")
    expect(hotel.reload.name).to eq("Original hotel")
  end

  it "creates and clears a salesperson assignment" do
    expect {
      patch update_salesperson_admin_hotel_path(hotel), params: { salesperson: { operation: "create", name: "New seller", email: "new-seller@example.com" } }
    }.to change { admin_account.users.where(role: "salesperson").count }.by(1)
    expect(hotel.reload.salesperson.name).to eq("New seller")

    patch update_salesperson_admin_hotel_path(hotel), params: { salesperson: { operation: "assign", id: "" } }
    expect(hotel.reload.salesperson).to be_nil
  end

  it "sends a reset link and lets the owner use it only once" do
    expect {
      post send_owner_password_reset_admin_hotel_path(hotel), params: { owner_id: owner.id }
    }.to have_enqueued_mail(OwnerPasswordResetMailer, :reset)

    reset = owner.owner_password_resets.last
    expect(reset).to be_present
    token = "known-reset-token"
    reset.update!(token_digest: Digest::SHA256.hexdigest(token))
    expect(OwnerPasswordResetMailer.reset(owner, hotel, token).body.encoded).to include(owner_password_reset_path(token))

    patch owner_password_reset_path(token), params: { password: "NewPassword123!", password_confirmation: "NewPassword123!" }
    expect(response).to redirect_to(login_path)
    expect(owner.reload.authenticate("NewPassword123!")).to eq(owner)

    patch owner_password_reset_path(token), params: { password: "AnotherPassword123!", password_confirmation: "AnotherPassword123!" }
    expect(response).to redirect_to(login_path)
    expect(owner.reload.authenticate("AnotherPassword123!")).to be(false)
  end

  it "rejects an expired reset link" do
    reset = OwnerPasswordReset.create!(user: owner, token_digest: Digest::SHA256.hexdigest("expired-token"), expires_at: 1.minute.ago)
    patch owner_password_reset_path("expired-token"), params: { password: "NewPassword123!", password_confirmation: "NewPassword123!" }
    expect(response).to redirect_to(login_path)
    expect(reset.reload.consumed_at).to be_nil
  end

  it "sets the selected owner password directly" do
    old_version = owner.auth_version
    patch set_owner_password_admin_hotel_path(hotel), params: {
      owner_id: owner.id, password: "NewPassword123!", password_confirmation: "NewPassword123!"
    }
    expect(response).to redirect_to(admin_hotel_path(hotel, tab: "account_information", owner_id: owner.id))
    expect(owner.reload.auth_version).to eq(old_version + 1)
    expect(owner.authenticate("NewPassword123!")).to eq(owner)
  end

  it "expires existing sessions after an admin sets the owner password" do
    get test_sign_in_path(owner.id)
    Admin::Hotels::ChangeOwnerPassword.call(user: owner, password: "NewPassword123!", password_confirmation: "NewPassword123!")
    get hotel_dashboard_path(hotel)
    expect(response).to redirect_to(login_path)
  end
end
