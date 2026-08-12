# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding commercial phase", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
  end

  def resolve_through!(last_key)
    Onboarding::InitializeProgress.new(hotel: hotel).call
    keys = Onboarding::SectionCatalog.keys
    keys[0..keys.index(last_key)].each do |key|
      hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
    end
  end

  def charge_entry(overrides = {})
    {
      "name" => "Airport transfer", "code" => "TRANSFER", "category" => "other",
      "pricing_type" => "fixed", "rate_value" => "80", "charging_unit" => "per_item",
      "allow_amount_override" => "true", "active" => "true", "_destroy" => "false"
    }.merge(overrides)
  end

  describe "extra charges" do
    it "stays locked until rates and availability resolve" do
      resolve_through!("rooms")

      get hotel_onboarding_section_path(hotel, section_key: "extra_charges")

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "rates_availability"))
    end

    context "once reachable" do
      before { resolve_through!("rates_availability") }

      it "offers the standard revenue codes as unsaved suggestions" do
        get hotel_onboarding_section_path(hotel, section_key: "extra_charges")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Food &amp; Beverage")
        expect(response.body).to include("suggestions, not saved yet")
        expect(hotel.hotel_extra_charges).to be_empty
      end

      it "saves and advances to discounts" do
        patch hotel_onboarding_section_path(hotel, section_key: "extra_charges"),
              params: { navigation_action: "save_continue", extra_charge_entries: { "0" => charge_entry } }

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "discounts"))
        expect(hotel.hotel_extra_charges.sole.name).to eq("Airport transfer")
        expect(hotel.onboarding_sections.find_by(section_key: "extra_charges").state).to eq("complete")
      end

      it "re-renders with the typed values when a row is invalid" do
        patch hotel_onboarding_section_path(hotel, section_key: "extra_charges"),
              params: {
                navigation_action: "save_continue",
                extra_charge_entries: { "0" => charge_entry("name" => "", "code" => "TRANSFER") }
              }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("TRANSFER")
        expect(hotel.hotel_extra_charges).to be_empty
      end

      it "records an explicit skip decision" do
        patch hotel_onboarding_section_path(hotel, section_key: "extra_charges"),
              params: { navigation_action: "skip" }

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "discounts"))
        section = hotel.onboarding_sections.find_by(section_key: "extra_charges")
        expect(section.state).to eq("skipped")
        expect(section.decision_metadata).to include("decision" => "no_extra_charges")
      end

      it "renders read-only once the property is pending review" do
        hotel.update!(status: "pending_review")

        get hotel_onboarding_section_path(hotel, section_key: "extra_charges")

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Add extra charge")
      end
    end
  end
end
