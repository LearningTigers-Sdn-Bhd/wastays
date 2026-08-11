# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel portal OTA financial settings", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, default_currency: "MYR") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "ota-finance-manager", name: "OTA Finance Manager") }
  let(:permission) do
    Permission.find_or_create_by!(slug: "manage_general_ledger_maps") do |record|
      record.name = "Manage general ledger maps"
    end
  end

  before do
    RolePermission.create!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/settings/finance/ota-financials" do
    it "renders accessible policy, preview, and mapping review controls" do
      code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other", code: "OTAFEE", system_key: "ota_fee")
      create(:ota_financial_component_mapping,
        hotel: hotel,
        booking_source: nil,
        transaction_code: code,
        normalized_provider_name: "aurora_service_fee")

      get hotel_ota_financial_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "OTA Financials" ])
      expect(document.at_css("fieldset[role='radiogroup'] legend").text.squish).to eq("Review sensitivity")
      expect(document.css("input[name='ota_financial_settings[mode]']").map { |input| input["value"] }).to eq(%w[recommended strict custom])
      expect(document.at_css("[data-ota-financial-settings-target='customFields'][aria-hidden='true']")).to be_present
      expect(document.at_css("[data-testid='aurora-rate-preview']").text).to include(
        "What would happen", "Aurora Crown reference", "MYR 1488.79", "MYR 1485.00", "Booking"
      )
      expect(document.at_css("table caption").text).to eq("OTA financial component mappings")
      expect(document.at_css(".panel-select-menu select[name*='mapping_transaction_code_ids']")).to be_present
      expect(document.text).to include("Bookings are always ingested")
      expect(document.text).not_to match(/reject(?:s|ed|ion)? the booking/i)
    end

    it "shows a useful empty mapping review state" do
      get hotel_ota_financial_settings_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No provider components to review")
    end

    it "does not expose another hotel's records" do
      other_hotel = create(:hotel)
      create(:ota_financial_component_mapping, hotel: other_hotel, normalized_provider_name: "private_fee")

      get hotel_ota_financial_settings_path(hotel)

      expect(response.body).not_to include("Private fee")
    end
  end

  describe "financial review adjustments" do
    it "surfaces and approves a pending posted-history adjustment" do
      posting_permission = Permission.find_or_create_by!(slug: "post_folio_adjustments") do |record|
        record.name = "Post folio adjustments"
      end
      RolePermission.create!(role: role, permission: posting_permission)
      booking = create(:booking, hotel: hotel)
      create(:booking_folio, booking: booking, hotel: hotel)
      snapshot = create(:ota_financial_snapshot, hotel: hotel, booking: booking,
        reconciliation_status: "rate_review_required",
        metadata: {
          "adjustment_proposal" => {
            "identity" => "portal-proposal", "status" => "pending", "currency" => "MYR",
            "amount" => "7.50", "allocations" => [ { "booking_id" => booking.id, "amount" => "7.50" } ]
          }
        })

      get hotel_ota_financial_settings_path(hotel)
      expect(response.body).to include("Financial review", "Approve and post adjustment", "MYR 7.50")

      post approve_adjustment_hotel_ota_financial_settings_path(hotel), params: { snapshot_id: snapshot.id }

      expect(response).to redirect_to(hotel_ota_financial_settings_path(hotel))
      expect(FolioTransaction.where("metadata->>'ota_adjustment_proposal_identity' = ?", "portal-proposal")).to exist
    end
  end

  describe "PATCH /hotel/:hotel_id/settings/finance/ota-financials" do
    it "persists a custom rate review policy" do
      patch hotel_ota_financial_settings_path(hotel), params: {
        ota_financial_settings: {
          mode: "custom",
          maximum_percentage: "2.5",
          maximum_amount_per_room_night: "15.00",
          mapping_transaction_code_ids: {}
        }
      }

      expect(response).to redirect_to(hotel_ota_financial_settings_path(hotel))
      policy = OtaRateVariancePolicy.find_by!(hotel: hotel)
      expect(policy).to have_attributes(
        mode: "custom",
        maximum_percentage: 2.5.to_d,
        maximum_amount_per_room_night: 15.to_d,
        currency: "MYR"
      )
    end

    it "applies recommended defaults rather than trusting submitted custom limits" do
      patch hotel_ota_financial_settings_path(hotel), params: {
        ota_financial_settings: {
          mode: "recommended",
          maximum_percentage: "99",
          maximum_amount_per_room_night: "999",
          mapping_transaction_code_ids: {}
        }
      }

      policy = OtaRateVariancePolicy.find_by!(hotel: hotel)
      expect(policy.maximum_percentage).to eq(1.to_d)
      expect(policy.maximum_amount_per_room_night).to eq(10.to_d)
    end

    it "updates a reviewed component mapping with a compatible hotel code" do
      old_code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other", code: "OLDOTA", system_key: "old_ota")
      new_code = create(:transaction_code, hotel: hotel, kind: "charge", category: "other", code: "NEWOTA", system_key: "new_ota")
      mapping = create(:ota_financial_component_mapping,
        hotel: hotel,
        booking_source: nil,
        transaction_code: old_code,
        normalized_provider_name: "aurora_service_fee")
      candidate = HotelPortal::OtaFinancialSettingsPresenter.new(
        hotel: hotel,
        policy: OtaRateVariancePolicy.new(hotel: hotel, mode: "recommended", currency: "MYR")
      ).mapping_candidates.first

      patch hotel_ota_financial_settings_path(hotel), params: {
        ota_financial_settings: {
          mode: "recommended",
          mapping_transaction_code_ids: { candidate.key => new_code.id }
        }
      }

      expect(response).to redirect_to(hotel_ota_financial_settings_path(hotel))
      expect(mapping.reload).to have_attributes(transaction_code_id: new_code.id, active: true, created_by_id: user.id)
    end

    it "renders validation errors without saving an invalid custom policy" do
      patch hotel_ota_financial_settings_path(hotel), params: {
        ota_financial_settings: {
          mode: "custom",
          maximum_percentage: "",
          maximum_amount_per_room_night: "-1",
          mapping_transaction_code_ids: {}
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.at_css("[role='alert']").text).to include("could not save")
      expect(OtaRateVariancePolicy.where(hotel: hotel)).not_to exist
    end
  end

  context "without financial mapping permission" do
    before do
      RolePermission.where(role: role, permission: permission).delete_all
    end

    it "denies viewing and updating the resource" do
      get hotel_ota_financial_settings_path(hotel)
      expect(response).to redirect_to(root_path)

      patch hotel_ota_financial_settings_path(hotel), params: {
        ota_financial_settings: { mode: "strict", mapping_transaction_code_ids: {} }
      }
      expect(response).to redirect_to(root_path)
      expect(OtaRateVariancePolicy.where(hotel: hotel)).not_to exist
    end
  end
end
