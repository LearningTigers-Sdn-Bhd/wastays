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

      it "reads an emptied table as the decision, without a skip button" do
        get hotel_onboarding_section_path(hotel, section_key: "extra_charges")
        expect(response.body).not_to include("navigation_action\" value=\"skip\"")

        patch hotel_onboarding_section_path(hotel, section_key: "extra_charges"),
              params: { navigation_action: "save_continue", extra_charge_entries: {} }

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

      it "reads an emptied table as the decision, without a skip button" do
        get hotel_onboarding_section_path(hotel, section_key: "discounts")
        expect(response.body).not_to include("navigation_action\" value=\"skip\"")

        patch hotel_onboarding_section_path(hotel, section_key: "discounts"),
              params: { navigation_action: "save_continue", discount_entries: {} }

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

    it "asks for a name and a type, and carries the rest hidden" do
      get hotel_onboarding_section_path(hotel, section_key: "payment_methods")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Surcharge")
      expect(response.body).to include("payment_method_entries[0][surcharge_enabled]")
    end

    # The standard codes are shown; only a row the owner adds is typed.
    it "shows the standard payment codes rather than offering them for editing" do
      get hotel_onboarding_section_path(hotel, section_key: "payment_methods")

      expect(response.body).to include("Cash Payment", "Card Payment")
      expect(response.body).not_to include("payment_method_entries[0][name]")
      expect(response.body).to include("payment_method_entries[NEW_RECORD][name]")
    end

    it "saves and advances to corporate accounts" do
      patch hotel_onboarding_section_path(hotel, section_key: "payment_methods"),
            params: {
              navigation_action: "save_continue",
              payment_method_entries: { "0" => {
                "name" => "Front desk cash", "code" => "", "payment_method_type" => "cash",
                "guest_advance" => "false", "default_cash" => "false", "active" => "true",
                "surcharge_enabled" => "false", "_destroy" => "false"
              } }
            }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"))
      expect(hotel.hotel_payment_methods.sole)
        .to have_attributes(name: "Front desk cash", code: "FRONT_DESK", default_cash: true)
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

    it "uses the page heading once and explains repeated fields from their column headers" do
      get hotel_onboarding_section_path(hotel, section_key: "corporate_accounts")

      document = Nokogiri::HTML(response.body)

      expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Corporate accounts" ])
      expect(document.at_css("section[aria-label='Corporate accounts']")).to be_present
      expect(document.at_css("h2#onboarding-corporate-accounts-heading")).to be_nil
      expect(document.at_css("thead th button[aria-label='Email: Where the invitation goes after submission.']")).to be_present
      expect(document.at_css("thead th button[aria-label='Credit limit: Leave blank for no limit.']")).to be_present
      expect(document.css("thead th").map { |header| header.text.strip }).not_to include("Billing")
      expect(document.at_css("[name*='[relationship_type]']")).to be_nil
      expect(document.at_css("input[name*='[credit_limit]'][placeholder='e.g. 5000.00']")).to be_present
      expect(document.at_css("input[name*='[payment_terms_days]'][placeholder='e.g. 30']")).to be_present
      expect(document.css("tbody .panel-form-field__hint")).to be_empty
    end

    it "queues a draft and advances to the channel manager without sending" do
      expect {
        patch hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"),
              params: {
                navigation_action: "save_continue",
                corporate_draft_entries: { "0" => {
                  "email" => "accounts@acme.com", "company_name" => "Acme Sdn Bhd",
                  "account_type" => "company",
                  "credit_currency" => "MYR", "payment_terms_days" => "30", "_destroy" => "false"
                } }
              }
      }.not_to change(Invitation, :count)

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "channel_manager"))
      expect(hotel.onboarding_corporate_drafts.sole)
        .to have_attributes(email: "accounts@acme.com", relationship_type: "direct_bill")
    end

    # The empty table is the decision. There is no separate skip button to press,
    # and continuing from an empty table records what one would have recorded.
    it "reads an empty table as the decision, without a skip button" do
      get hotel_onboarding_section_path(hotel, section_key: "corporate_accounts")
      expect(response.body).not_to include("navigation_action\" value=\"skip\"")

      patch hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"),
            params: { navigation_action: "save_continue", corporate_draft_entries: {} }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "channel_manager"))
      section = hotel.onboarding_sections.find_by(section_key: "corporate_accounts")
      expect(section.state).to eq("skipped")
      expect(section.decision_metadata).to include("decision" => "no_corporate_accounts")
    end
  end

  describe "channel manager" do
    before { resolve_through!("corporate_accounts") }

    def credential_entry(overrides = {})
      {
        "channel_name" => "Booking.com", "property_code" => "623847",
        "username" => "acme-hotel", "password" => "extranet-secret",
        "market_manager_name" => "Dana Lim", "market_manager_phone" => "+60 12 345 6789",
        "market_manager_email" => "dana@booking.com", "_destroy" => "false"
      }.merge(overrides)
    end

    it "says who reads the credentials and that nothing connects from here" do
      get hotel_onboarding_section_path(hotel, section_key: "channel_manager")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Only the WAStays team reads these")
      expect(response.body).to include("Nothing is connected from this page")
    end

    it "uses the page heading once and explains repeated fields from their column headers" do
      get hotel_onboarding_section_path(hotel, section_key: "channel_manager")

      document = Nokogiri::HTML(response.body)

      expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Channel manager" ])
      expect(document.at_css("section[aria-label='Channel manager']")).to be_present
      expect(document.at_css("thead th button[aria-label=\"Channel: The extranet these details sign in to, such as Booking.com.\"]")).to be_present
      expect(document.css("tbody .panel-form-field__hint")).to be_empty
    end

    it "names the provider WAStays chose for this property" do
      hotel.update!(preferred_channel_manager: "channex")

      get hotel_onboarding_section_path(hotel, section_key: "channel_manager")

      expect(response.body).to include("WAStays set this property up for Channex")
    end

    it "says nothing about a provider when the choice was left open" do
      hotel.update!(preferred_channel_manager: "undecided")

      get hotel_onboarding_section_path(hotel, section_key: "channel_manager")

      expect(response.body).not_to include("WAStays set this property up for")
      expect(response.body).to include("connect each channel after approval")
    end

    it "stores the login encrypted and advances to review" do
      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: { navigation_action: "save_continue", ota_credential_entries: { "0" => credential_entry } }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "review"))
      credential = hotel.hotel_ota_credentials.sole
      expect(credential).to have_attributes(
        channel_name: "Booking.com", property_code: "623847",
        username: "acme-hotel", password: "extranet-secret",
        market_manager_email: "dana@booking.com", status: "pending"
      )

      # The columns hold ciphertext, not what was typed.
      raw = HotelOtaCredential.connection.select_one(
        "SELECT username, password FROM hotel_ota_credentials WHERE id = #{credential.id}"
      )
      expect(raw["password"]).not_to include("extranet-secret")
      expect(raw["username"]).not_to include("acme-hotel")
    end

    it "never renders a stored password back into the form" do
      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: { navigation_action: "save_draft", ota_credential_entries: { "0" => credential_entry } }

      get hotel_onboarding_section_path(hotel, section_key: "channel_manager")

      expect(response.body).not_to include("extranet-secret")
      document = Nokogiri::HTML(response.body)
      password_field = document.at_css("input[type='password'][name*='[password]']")
      expect(password_field["value"]).to be_blank
      expect(password_field["placeholder"]).to eq("Saved — leave blank to keep")
    end

    it "keeps the stored password when the owner saves the row without retyping it" do
      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: { navigation_action: "save_draft", ota_credential_entries: { "0" => credential_entry } }
      credential = hotel.hotel_ota_credentials.sole

      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: {
              navigation_action: "save_continue",
              ota_credential_entries: { "0" => credential_entry(
                "id" => credential.id.to_s, "password" => "", "market_manager_phone" => "+60 12 000 1111"
              ) }
            }

      expect(credential.reload).to have_attributes(
        password: "extranet-secret", market_manager_phone: "+60 12 000 1111"
      )
    end

    it "rejects two rows for the same channel without echoing the password back" do
      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: {
              navigation_action: "save_continue",
              ota_credential_entries: {
                "0" => credential_entry,
                "1" => credential_entry("property_code" => "999999")
              }
            }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Each channel needs its own row")
      expect(response.body).not_to include("extranet-secret")
      expect(response.body).to include("Re-enter to save")
      expect(hotel.hotel_ota_credentials).to be_empty
    end

    it "takes continuing from an empty table as the answer, with no separate skip button" do
      hotel.update!(preferred_channel_manager: "channex")

      get hotel_onboarding_section_path(hotel, section_key: "channel_manager")
      expect(response.body).not_to include("No channel manager for now")

      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: { navigation_action: "save_continue", ota_credential_entries: {} }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "review"))
      section = hotel.onboarding_sections.find_by(section_key: "channel_manager")
      expect(section.state).to eq("skipped")
      expect(section.decision_metadata).to include("decision" => "no_channel_manager_now")
      # Skipping the connection must not throw away the admin's provider choice.
      expect(hotel.reload.preferred_channel_manager).to eq("channex")
    end
  end

  # The point of the phase: five resolved sections stop blocking submission.
  describe "readiness" do
    it "no longer reports the commercial sections as blocking" do
      resolve_through!("rates_availability")

      # In catalog order: each answer needs its own prerequisite resolved first.
      # No section takes a skip action — an emptied table is the answer.
      %w[extra_charges discounts].each do |key|
        patch hotel_onboarding_section_path(hotel, section_key: key),
              params: { navigation_action: "save_continue", "#{key.singularize}_entries" => {} }
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
      # Corporate accounts and the channel manager have no skip button: an empty
      # table, continued from, is the same answer.
      patch hotel_onboarding_section_path(hotel, section_key: "corporate_accounts"),
            params: { navigation_action: "save_continue", corporate_draft_entries: {} }
      patch hotel_onboarding_section_path(hotel, section_key: "channel_manager"),
            params: { navigation_action: "save_continue", ota_credential_entries: {} }

      blocking = Onboarding::Readiness.new(hotel: hotel.reload).call.blocking_issues.map(&:section_key)
      expect(blocking).not_to include("extra_charges", "discounts", "payment_methods", "corporate_accounts", "channel_manager")
    end
  end
end
