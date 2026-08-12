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
      "name" => "Airport transfer", "code" => "", "rate_value" => "80",
      "charging_unit" => "per_item", "_destroy" => "false"
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
                extra_charge_entries: { "0" => charge_entry("rate_value" => "0") }
              }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Airport transfer")
        expect(hotel.hotel_extra_charges).to be_empty
      end

      # The table asks for a name, not an accounting code.
      it "names the charge without asking for a code" do
        patch hotel_onboarding_section_path(hotel, section_key: "extra_charges"),
              params: { navigation_action: "save_continue", extra_charge_entries: { "0" => charge_entry } }

        expect(hotel.hotel_extra_charges.sole.code).to eq("AIRPORT_TR")
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

  describe "discounts" do
    it "stays locked until extra charges resolve" do
      resolve_through!("rates_availability")

      get hotel_onboarding_section_path(hotel, section_key: "discounts")

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "extra_charges"))
    end

    context "once reachable" do
      before { resolve_through!("extra_charges") }

      it "offers eligible charges even when extra charges were skipped" do
        hotel.onboarding_sections.find_by!(section_key: "extra_charges").update!(state: "skipped")

        get hotel_onboarding_section_path(hotel, section_key: "discounts")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Extra charges were skipped")
        expect(response.body).to include("Food &amp; Beverage (FNB)")
      end

      # The room and its own charges are what the scope above the picker already
      # means, so naming them again inside it would be a worse way to say it.
      it "keeps the room and its charges out of the charge picker" do
        get hotel_onboarding_section_path(hotel, section_key: "discounts")

        expect(response.body).not_to include("Room Revenue (ROOM)")
        expect(response.body).not_to include("Cancellation Revenue (CANCEL)")
      end

      # The settings portal can pin anything the join row accepts. A picker that
      # cannot show a selection would drop it on the next save.
      it "keeps showing a room charge a discount already pins" do
        discount = Discounts::Save.call(
          discount: HotelDiscount.new(hotel: hotel, transaction_code: TransactionCode.new(hotel: hotel)),
          attributes: {
            name: "Manager courtesy", code: "MGRDISC", active: "true", pricing_type: "manual",
            application_scope: "selected_charges",
            applicable_transaction_code_ids: [ hotel.transaction_codes.find_by!(system_key: "room_revenue").id.to_s ]
          }
        )
        expect(discount.success?).to be(true)

        get hotel_onboarding_section_path(hotel, section_key: "discounts")

        expect(response.body).to include("Room Revenue (ROOM)")
      end

      it "saves and advances to payment methods" do
        patch hotel_onboarding_section_path(hotel, section_key: "discounts"),
              params: {
                navigation_action: "save_continue",
                discount_entries: { "0" => {
                  "name" => "Early bird", "pricing_type" => "percentage",
                  "rate_value" => "10", "application_scope" => "all_eligible_charges",
                  "_destroy" => "false"
                } }
              }

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "payment_methods"))
        # The table asks for a name, not an accounting code.
        expect(hotel.hotel_discounts.sole).to have_attributes(name: "Early bird", code: "EARLY_BIRD")
      end

      # An offer whose amount staff decide has no rate at all, so the table shows
      # no amount field for it — and must not carry one over from a row that had.
      it "drops the rate when the method is one staff price themselves" do
        patch hotel_onboarding_section_path(hotel, section_key: "discounts"),
              params: {
                navigation_action: "save_continue",
                discount_entries: { "0" => {
                  "name" => "Goodwill rebate", "pricing_type" => "manual", "rate_value" => "25",
                  "application_scope" => "all_eligible_charges", "_destroy" => "false"
                } }
              }

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "payment_methods"))
        expect(hotel.hotel_discounts.sole).to have_attributes(pricing_type: "manual", rate_value: nil)
      end

      it "records an explicit skip decision" do
        patch hotel_onboarding_section_path(hotel, section_key: "discounts"),
              params: { navigation_action: "skip" }

        expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "payment_methods"))
        section = hotel.onboarding_sections.find_by(section_key: "discounts")
        expect(section.state).to eq("skipped")
        expect(section.decision_metadata).to include("decision" => "no_discounts")
      end
    end
  end

  describe "payment methods" do
    before { resolve_through!("discounts") }

    it "offers no skip and rejects a forged one" do
      get hotel_onboarding_section_path(hotel, section_key: "payment_methods")
      expect(response.body).not_to include("navigation_action\" value=\"skip\"")

      patch hotel_onboarding_section_path(hotel, section_key: "payment_methods"),
            params: { navigation_action: "skip" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(hotel.onboarding_sections.find_by(section_key: "payment_methods").state).not_to eq("skipped")
    end

    it "switches the surcharge columns off when there is nothing to post to" do
      get hotel_onboarding_section_path(hotel, section_key: "payment_methods")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Surcharges need an extra charge to post to")
      expect(response.body).to include("No extra charges to post to")
    end

    it "saves and advances to corporate accounts" do
      patch hotel_onboarding_section_path(hotel, section_key: "payment_methods"),
            params: {
              navigation_action: "save_continue",
              payment_method_entries: { "0" => {
                "name" => "Cash", "code" => "CASHDESK", "payment_method_type" => "cash",
                "guest_advance" => "false", "default_cash" => "true", "active" => "true",
                "surcharge_enabled" => "false", "_destroy" => "false"
              } }
            }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"))
      expect(hotel.hotel_payment_methods.sole.name).to eq("Cash")
      expect(hotel.onboarding_sections.find_by(section_key: "payment_methods").state).to eq("complete")
    end
  end

  describe "corporate accounts" do
    before { resolve_through!("payment_methods") }

    it "says plainly that nothing is sent during setup" do
      get hotel_onboarding_section_path(hotel, section_key: "corporate_accounts")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No invitations are sent yet")
    end

    it "queues a draft and advances to the channel manager without sending" do
      expect {
        patch hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"),
              params: {
                navigation_action: "save_continue",
                corporate_draft_entries: { "0" => {
                  "email" => "accounts@acme.com", "company_name" => "Acme Sdn Bhd",
                  "account_type" => "company", "relationship_type" => "direct_bill",
                  "credit_currency" => "MYR", "payment_terms_days" => "30", "_destroy" => "false"
                } }
              }
      }.not_to change(Invitation, :count)

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "channel_manager"))
      expect(hotel.onboarding_corporate_drafts.sole.email).to eq("accounts@acme.com")
    end

    it "records an explicit skip decision" do
      patch hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"),
            params: { navigation_action: "skip" }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "channel_manager"))
      section = hotel.onboarding_sections.find_by(section_key: "corporate_accounts")
      expect(section.state).to eq("skipped")
      expect(section.decision_metadata).to include("decision" => "no_corporate_accounts")
    end
  end

  # The point of the phase: four resolved sections stop blocking submission.
  describe "readiness" do
    it "no longer reports the commercial sections as blocking" do
      resolve_through!("rates_availability")

      # In catalog order: each skip needs its own prerequisite resolved first.
      %w[extra_charges discounts].each do |key|
        patch hotel_onboarding_section_path(hotel, section_key: key), params: { navigation_action: "skip" }
      end
      patch hotel_onboarding_section_path(hotel, section_key: "payment_methods"),
            params: {
              navigation_action: "save_continue",
              payment_method_entries: { "0" => {
                "name" => "Cash", "code" => "CASHDESK", "payment_method_type" => "cash",
                "guest_advance" => "false", "default_cash" => "true", "active" => "true",
                "surcharge_enabled" => "false", "_destroy" => "false"
              } }
            }
      patch hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"),
            params: { navigation_action: "skip" }

      blocking = Onboarding::Readiness.new(hotel: hotel.reload).call.blocking_issues.map(&:section_key)
      expect(blocking).not_to include("extra_charges", "discounts", "payment_methods", "corporate_accounts")
    end
  end
end
