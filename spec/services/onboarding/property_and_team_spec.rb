# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding property and team services" do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }

  it "does not complete a property profile without its required details" do
    result = Onboarding::SavePropertyProfile.new(
      hotel: hotel,
      actor: actor,
      complete: true,
      params: ActionController::Parameters.new(
        hotel: { name: hotel.name, default_currency: "MYR" },
        property_policy: { check_in_time: "15:00", check_out_time: "11:00" }
      )
    ).call

    expect(result.success?).to be(false)
    expect(result.error).to include("Contact email", "Timezone")
  end

  it "saves the front desk landline and the business day window alongside the profile" do
    result = Onboarding::SavePropertyProfile.new(
      hotel: hotel,
      actor: actor,
      complete: false,
      params: ActionController::Parameters.new(
        hotel: { name: hotel.name, fixed_line_number: "03-2144 1234", business_starts_at: "07:00", business_ends_at: "01:30" },
        property_policy: { check_in_time: "15:00", check_out_time: "11:00" }
      )
    ).call

    expect(result.success?).to be(true)
    expect(hotel.reload.fixed_line_number).to eq("03-2144 1234")
    expect(hotel.business_starts_at.strftime("%H:%M")).to eq("07:00")
    expect(hotel.business_ends_at.strftime("%H:%M")).to eq("01:30")
  end

  # The step used to carry a checkbox saying the owner had read the presets. The
  # fingerprint is what that click was really for, so saving the step writes it
  # with no checkbox to tick.
  it "records a permission snapshot when the team step is saved" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "complete")
    hotel.onboarding_sections.find_by!(section_key: "property_photos").update!(state: "complete")

    result = Onboarding::SaveTeamSetup.new(hotel: hotel, actor: actor, entries: {}, complete: true).call

    expect(result.success?).to be(true)
    expect(result.section).to have_attributes(state: "complete")
    expect(result.section.decision_metadata).to include(
      "source" => "team_setup",
      "confirmed_role_slugs" => Onboarding::RolePresets::PRESET_SLUGS,
      "permission_fingerprint" => be_present,
      "decision" => "no_additional_staff"
    )
    expect(Onboarding::Readiness.new(hotel: hotel).call.blocking_issues.map(&:section_key))
      .not_to include("team_setup")
  end

  it "blocks submission again when a preset role loses a permission after the save" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "complete")
    hotel.onboarding_sections.find_by!(section_key: "property_photos").update!(state: "complete")
    Onboarding::SaveTeamSetup.new(hotel: hotel, actor: actor, entries: {}, complete: true).call

    RolePermission.create!(
      role: hotel.account.roles.find_by!(slug: "front_desk"),
      permission: Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View bookings" }
    )

    issues = Onboarding::Readiness.new(hotel: hotel).call.blocking_issues
    expect(issues.map(&:code)).to include(:roles_changed)
  end

  it "keeps invalid staff rows out of persistent drafts" do
    HotelOps::SeedAccountRoles.call(hotel.account)
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "complete")
    hotel.onboarding_sections.find_by!(section_key: "property_photos").update!(state: "complete")

    result = Onboarding::SaveTeamSetup.new(
      hotel: hotel,
      actor: actor,
      complete: true,
      entries: { "0" => { email: "not-an-email", role_id: hotel.account.roles.find_by!(slug: "front_desk").id } }
    ).call

    expect(result.success?).to be(false)
    expect(hotel.onboarding_staff_drafts).to be_empty
  end
  describe "the send-invitation switch on staff drafts" do
    let(:role) { hotel.account.roles.find_by!(slug: "front_desk") }

    before do
      HotelOps::SeedAccountRoles.call(hotel.account)
      Onboarding::InitializeProgress.new(hotel: hotel).call
      hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "complete")
      hotel.onboarding_sections.find_by!(section_key: "property_photos").update!(state: "complete")
          end

    def save(entries, complete: true)
      Onboarding::SaveTeamSetup.new(hotel: hotel, actor: actor, entries: entries, complete: complete).call
    end

    def entry(overrides = {})
      { email: "aliya@example.com", name: "Aliya", role_id: role.id }.merge(overrides)
    end

    it "holds the person by default, because listing a colleague is not asking us to email them" do
      expect(save({ "0" => entry }).success?).to be(true)
      expect(hotel.onboarding_staff_drafts.sole.send_invitation).to be(false)
    end

    it "records the owner switching it on" do
      expect(save({ "0" => entry(send_invitation: "1") }).success?).to be(true)
      expect(hotel.onboarding_staff_drafts.sole.send_invitation).to be(true)
    end

    # The switch submits on every row, off included, so it must not make an
    # untouched row look like a record someone meant to add.
    it "still discards a row the owner never filled in" do
      result = save({ "0" => entry, "1" => { email: "", name: "", role_id: "", send_invitation: "0" } })

      expect(result.success?).to be(true)
      expect(hotel.onboarding_staff_drafts.count).to eq(1)
    end

    it "saves the same table twice without tripping over its own rows" do
      expect(save({ "0" => entry }).success?).to be(true)

      result = save({ "0" => entry(name: "Aliya Yusoff", send_invitation: "1") })

      expect(result.success?).to be(true)
      expect(hotel.onboarding_staff_drafts.sole).to have_attributes(name: "Aliya Yusoff", send_invitation: true)
    end

    context "after the drafts have been delivered" do
      before do
        save({ "0" => entry })
        Onboarding::DeliverInvitations.call(hotel: hotel, actor: actor)
      end

      it "keeps the delivery marker when the step is edited again" do
        invitation_id = hotel.onboarding_staff_drafts.sole.invitation_id

        expect(save({ "0" => entry(name: "Aliya Yusoff") }).success?).to be(true)
        expect(hotel.onboarding_staff_drafts.sole.invitation_id).to eq(invitation_id)
      end

      it "refuses to drop someone who has already been invited" do
        result = save({ "0" => entry(email: "someone-else@example.com") })

        expect(result.success?).to be(false)
        expect(result.error).to include("already been invited")
        expect(hotel.onboarding_staff_drafts.sole.email).to eq("aliya@example.com")
      end
    end
  end

  it "rejects a draft for someone who already has property access" do
    HotelOps::SeedAccountRoles.call(hotel.account)
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "complete")
    hotel.onboarding_sections.find_by!(section_key: "property_photos").update!(state: "complete")
        existing_user = create(:user, account: hotel.account, email: "existing@example.com")
    create(:user_hotel_access, hotel: hotel, user: existing_user, role: hotel.account.roles.find_by!(slug: "front_desk"))

    result = Onboarding::SaveTeamSetup.new(
      hotel: hotel,
      actor: actor,
      complete: true,
      entries: { "0" => { email: existing_user.email, role_id: hotel.account.roles.find_by!(slug: "housekeeper").id } }
    ).call

    expect(result.success?).to be(false)
    expect(result.error).to include("already have access")
  end
end
