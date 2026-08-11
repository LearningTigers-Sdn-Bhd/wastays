# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding shell", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:property_params) do
    {
      name: hotel.name,
      address: "12 Beach Road",
      city: "Kuala Lumpur",
      country: "Malaysia",
      time_zone: "Kuala Lumpur",
      default_currency: "MYR",
      contact_email: "stay@example.com",
      contact_phone: "+60312345678"
    }
  end

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "resolves the onboarding root to the first incomplete section" do
    get hotel_onboarding_path(hotel)

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.count).to eq(13)
  end

  it "renders the dedicated shell with accessible phase navigation" do
    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Onboarding progress")
    expect(response.body).to include("Property profile")
    expect(response.body).to include("Save draft")
    expect(response.body).not_to include("Open navigation")
  end

  it "redirects a locked deep link to the earliest unmet prerequisite" do
    get hotel_onboarding_section_path(hotel, section_key: "taxes_fees")

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    follow_redirect!
    expect(response.body).to include("Complete the earlier onboarding steps")
  end

  it "saves a draft without completing the section" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft", hotel: property_params }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("in_progress")
  end

  it "requires the property completion contract before advancing" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: {
            navigation_action: "save_continue",
            hotel: property_params,
            property_policy: { check_in_time: "15:00", check_out_time: "11:00" }
          }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Featured photo")
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("not_started")
  end

  it "saves a complete property profile and advances without placeholder metadata" do
    hotel.photos.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/sample_image.jpg")),
      filename: "property.jpg",
      content_type: "image/jpeg"
    )
    hotel.update!(featured_photo_attachment_id: hotel.photos.attachments.last.id)

    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: {
            navigation_action: "save_continue",
            hotel: property_params,
            property_policy: { check_in_time: "15:00", check_out_time: "11:00" }
          }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "roles_permissions"))
    section = hotel.onboarding_sections.find_by!(section_key: "property_profile")
    expect(section).to have_attributes(state: "complete", decision_metadata: include("source" => "property_profile"))
    expect(section.decision_metadata).not_to have_key("placeholder")
  end

  it "shows and confirms the four seeded role presets regardless of plan feature access" do
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")

    get hotel_onboarding_section_path(hotel, section_key: "roles_permissions")
    expect(response).to have_http_status(:ok)

    patch hotel_onboarding_section_path(hotel, section_key: "roles_permissions"),
          params: { navigation_action: "save_continue", confirm_presets: "1" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "staff_setup"))
    follow_redirect!
    expect(response.body).to include("Add staff member", "No additional staff for now")
    expect(account.roles.where(slug: Onboarding::ConfirmRolePresets::PRESET_SLUGS).count).to eq(4)
    expect(hotel.onboarding_sections.find_by!(section_key: "roles_permissions").decision_metadata)
      .to include("permission_fingerprint" => be_present)
  end

  it "stores staff drafts without sending invitations" do
    HotelOps::SeedAccountRoles.call(account)
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")
    staff_role = account.roles.find_by!(slug: "front_desk")

    invitation_count = StaffInvitation.count
    delivery_count = ActionMailer::Base.deliveries.count
    expect {
      patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
            params: {
              navigation_action: "save_continue",
              staff_entries: { "0" => { name: "Ari", email: "ARI@example.com", role_id: staff_role.id } }
            }
    }.to change(OnboardingStaffDraft, :count).by(1)

    expect(StaffInvitation.count).to eq(invitation_count)
    expect(ActionMailer::Base.deliveries.count).to eq(delivery_count)
    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_staff_drafts.first).to have_attributes(email: "ari@example.com", role: staff_role)
  end

  it "records the explicit no-additional-staff decision and clears drafts" do
    HotelOps::SeedAccountRoles.call(account)
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")
    create(:onboarding_staff_draft, hotel: hotel, role: account.roles.find_by!(slug: "housekeeper"))

    patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
          params: { navigation_action: "skip" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_staff_drafts).to be_empty
    expect(hotel.onboarding_sections.find_by!(section_key: "staff_setup")).to have_attributes(
      state: "skipped",
      decision_metadata: include("decision" => "no_additional_staff")
    )
  end

  it "allows optional steps to be explicitly skipped" do
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")

    patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
          params: { navigation_action: "skip" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_sections.find_by!(section_key: "staff_setup").state).to eq("skipped")
  end

  it "keeps pending-review onboarding read-only" do
    hotel.update!(status: "pending_review")

    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("not_started")

    follow_redirect!
    expect(response.body).to include("Setup submitted for review")
    expect(response.body).not_to include("Save draft")
  end

  it "presents requested changes in the affected section" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "needs_attention")
    hotel.onboarding_audit_events.create!(
      user: user,
      event_type: "changes_requested",
      section_key: "property_profile",
      metadata: { explanation: "Add a clear exterior photo." },
      occurred_at: Time.current
    )

    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Changes requested")
    expect(response.body).to include("Add a clear exterior photo.")
  end

  describe "finance phase" do
    def resolve_team_phase!
      Onboarding::InitializeProgress.new(hotel: hotel).call
      %w[property_profile roles_permissions staff_setup].each do |key|
        hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
      end
    end

    before { resolve_team_phase! }

    it "renders the taxes and fees form" do
      get hotel_onboarding_section_path(hotel, section_key: "taxes_fees")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Service Tax (SST)", "Tourism Tax (TTx)", "Add tax or fee")
      expect(response.body).to include("I confirm these are the taxes and fees this property charges")
    end

    it "refuses to complete taxes without the confirmation" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_continue", hotel: { sst_enabled: "1", tourism_tax_enabled: "0" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Confirm that you reviewed")
      expect(hotel.onboarding_sections.find_by!(section_key: "taxes_fees").state).not_to eq("complete")
    end

    it "completes taxes and advances to room revenue" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: {
              navigation_action: "save_continue",
              confirm_taxes: "1",
              hotel: { sst_enabled: "1", tourism_tax_enabled: "0", tourism_tax_amount: "10.0" },
              tax_entries: { "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" } }
            }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "room_revenue"))
      expect(hotel.onboarding_sections.find_by!(section_key: "taxes_fees").state).to eq("complete")
      expect(hotel.hotel_taxes.pluck(:name)).to eq([ "Heritage levy" ])
    end

    it "locks room revenue until taxes are resolved" do
      get hotel_onboarding_section_path(hotel, section_key: "room_revenue")

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    end

    it "renders and completes room revenue" do
      hotel.onboarding_sections.find_by!(section_key: "taxes_fees").update!(state: "complete")

      get hotel_onboarding_section_path(hotel, section_key: "room_revenue")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Taxes and fees applied", "Posting preview")

      patch hotel_onboarding_section_path(hotel, section_key: "room_revenue"),
            params: {
              navigation_action: "save_continue",
              transaction_code: { tax_rule_keys: [ "primary:sst_tax" ] },
              hotel_transaction_configuration: { room_revenue_tax_rule_application: "new_bookings_only" }
            }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "rooms"))
      expect(hotel.onboarding_sections.find_by!(section_key: "room_revenue").state).to eq("complete")
      expect(TransactionCodes::Resolver.for(hotel).room_revenue.transaction_code_taxes.map(&:tax_rule_key))
        .to eq([ "primary:sst_tax" ])
    end

    it "rejects a tax rule that does not belong to the hotel" do
      hotel.onboarding_sections.find_by!(section_key: "taxes_fees").update!(state: "complete")
      foreign_tax = create(:hotel_tax, hotel: create(:hotel))

      patch hotel_onboarding_section_path(hotel, section_key: "room_revenue"),
            params: {
              navigation_action: "save_continue",
              transaction_code: { tax_rule_keys: [ "hotel_tax:#{foreign_tax.id}" ] }
            }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("unavailable for this hotel")
    end

    it "explains why room revenue needs attention after a tax change" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_continue", confirm_taxes: "1", hotel: { sst_enabled: "1", tourism_tax_enabled: "0" } }
      patch hotel_onboarding_section_path(hotel, section_key: "room_revenue"),
            params: { navigation_action: "save_continue", transaction_code: { tax_rule_keys: [ "primary:sst_tax" ] } }

      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_continue", confirm_taxes: "1", hotel: { sst_enabled: "0", tourism_tax_enabled: "0" } }

      expect(hotel.onboarding_sections.find_by!(section_key: "room_revenue").state).to eq("needs_attention")

      get hotel_onboarding_section_path(hotel, section_key: "room_revenue")
      expect(response.body).to include("The taxes assigned to room revenue changed.")
    end
  end

  it "does not expose another hotel's onboarding" do
    other_hotel = create(:hotel, status: "setup")

    get hotel_onboarding_path(other_hotel)

    expect(response).to redirect_to(root_path)
  end
end
