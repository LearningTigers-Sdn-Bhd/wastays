require "rails_helper"

RSpec.describe "HotelPortal::TransactionCodes", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered", sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10) }
  let!(:service_charge) { create(:hotel_tax, hotel: hotel, name: "Service Charge", rate_type: "percentage", amount: 10.0) }
  let!(:inactive_fee) { create(:hotel_tax, hotel: hotel, name: "Inactive Levy", rate_type: "flat", amount: 2.0, enabled: false) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:manage_profile_permission) do
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
  end

  before do
    RolePermission.find_or_create_by!(role: role, permission: manage_profile_permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def form_option_values(field)
    Nokogiri::HTML(response.body).css("select[name='transaction_code[#{field}]'] option").map { |option| option["value"] }
  end

  def form_select_present?(field)
    Nokogiri::HTML(response.body).at_css("select[name='transaction_code[#{field}]']").present?
  end

  describe "GET /hotel/:hotel_id/transaction-codes" do
    it "renders the transaction codes page with default code list" do
      get hotel_transaction_codes_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Transaction Codes")
      expect(response.body).to include("Configure transaction codes used when posting charges, refunds, payments, and adjustments to guest folios.")
      expect(response.body).to include("Default Codes")
      expect(response.body).to include("Additional Service Codes")
      expect(response.body).to include("Configuration")
      expect(response.body).to include("Room Revenue Settings")
      expect(response.body).to include("Apply changes to")
      expect(response.body).to include("New bookings only")
      expect(response.body).to include("New bookings + upcoming transactions on open folios")
      expect(response.body).to include("Hotel Operations")
      expect(response.body).to include("Booking Operations")
      expect(response.body).to include("Utility Operations")
      expect(response.body).to include("Tax Operations")
      expect(response.body).to include("Manage Taxes &amp; Fees")
      expect(response.body).to include(hotel_taxes_fees_path(hotel))
      expect(response.body).to include("target=\"_blank\"")
      expect(response.body).to include("ROOM")
      expect(response.body).to include("TAX_SST")
      expect(response.body).to include("TAX_TTX")
      expect(response.body).to include("TAX_SC")
      expect(response.body).to include("Service Charge")
      expect(response.body).to include("Inactive Levy")
      expect(response.body).to include("bg-slate-100 text-slate-600 ring-slate-200")
      expect(response.body).to include("REBATE")
      expect(response.body).to include("GATEWAY")
      expect(response.body).to include("OTA")
      expect(response.body).to include("Gateway Manual Recovery")
      expect(response.body).to include("OTA Collected")
      expect(response.body).to include("Hotel-specific non-tax transaction codes for additional service postings.")
      expect(response.body).not_to include("Tax Listing")
    end
  end

  describe "PATCH /hotel/:hotel_id/transaction-codes/configuration" do
    it "creates and updates the hotel transaction configuration from radio card options" do
      expect {
        patch hotel_transaction_code_configuration_path(hotel), params: {
          hotel_transaction_configuration: {
            room_revenue_tax_rule_application: "open_folio_forecasts"
          }
        }
      }.to change { HotelTransactionConfiguration.where(hotel: hotel).count }.from(0).to(1)

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "configuration"))
      expect(hotel.reload.transaction_configuration.room_revenue_tax_rule_application).to eq("open_folio_forecasts")

      patch hotel_transaction_code_configuration_path(hotel), params: {
        hotel_transaction_configuration: {
          room_revenue_tax_rule_application: "new_bookings_only"
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "configuration"))
      expect(hotel.reload.transaction_configuration.room_revenue_tax_rule_application).to eq("new_bookings_only")
    end

    it "refreshes open folio forecasts when the open folio option is saved" do
      allow(Folios::RefreshOpenForecastsFromRoomRevenueRules).to receive(:call)

      patch hotel_transaction_code_configuration_path(hotel), params: {
        hotel_transaction_configuration: {
          room_revenue_tax_rule_application: "open_folio_forecasts"
        }
      }

      expect(Folios::RefreshOpenForecastsFromRoomRevenueRules).to have_received(:call).with(hotel: hotel, actor: user)
    end
  end

  describe "GET /hotel/:hotel_id/transaction-codes/:id/edit" do
    it "renders the transaction code offcanvas form" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")

      get hotel_edit_transaction_code_path(hotel, code)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Transaction Code: FNB")
      expect(response.body).to include("Tax Rules")
      expect(response.body).to include("SST 8%")
      expect(response.body).to include("Tourism Tax")
      expect(response.body).to include("Service Charge")
      expect(response.body).to include("Inactive")
    end

    it "does not show tax options when editing a non-tax transaction code" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")

      get hotel_edit_transaction_code_path(hotel, code)

      expect(response).to have_http_status(:ok)
      expect(form_option_values(:kind)).not_to include("tax")
      expect(form_option_values(:category)).not_to include("tax")
    end

    it "shows primary tax transaction code kind and category without selectors" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "sst_tax")

      get hotel_edit_transaction_code_path(hotel, code)

      expect(response).to have_http_status(:ok)
      expect(form_select_present?(:kind)).to be(false)
      expect(form_select_present?(:category)).to be(false)
      expect(response.body).to include("Tax")
      expect(response.body).to include("value=\"tax\"")
    end

    it "shows additional tax transaction code kind and category without selectors" do
      code = service_charge.reload.transaction_code

      get hotel_edit_transaction_code_path(hotel, code)

      expect(response).to have_http_status(:ok)
      expect(form_select_present?(:kind)).to be(false)
      expect(form_select_present?(:category)).to be(false)
      expect(response.body).to include("Service Charge")
      expect(response.body).to include("value=\"tax\"")
    end
  end

  describe "GET /hotel/:hotel_id/transaction-codes/new" do
    it "does not show tax options when creating an additional transaction code" do
      get hotel_new_transaction_code_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(form_option_values(:kind)).not_to include("tax")
      expect(form_option_values(:category)).not_to include("tax")
    end
  end

  describe "PATCH /hotel/:hotel_id/transaction-codes/:id" do
    it "updates an existing default transaction code and tax rules" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")

      patch hotel_transaction_code_path(hotel, code), params: {
        transaction_code: {
          code: "PARKING",
          name: "Parking Revenue",
          kind: "charge",
          category: "parking",
          active: "1",
          gl_account_code: "4091",
          is_taxable: "1",
          tax_rule_keys: [ "primary:sst_tax", "primary:tourism_tax", "hotel_tax:#{service_charge.id}", "hotel_tax:#{inactive_fee.id}" ]
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "default_codes"))
      expect(code.reload.code).to eq("PARKING")
      expect(code.name).to eq("Parking Revenue")
      expect(code.gl_account_code).to eq("4091")
      expect(code).to be_is_taxable
      expect(code.taxes).to match_array([ service_charge, inactive_fee ])
      expect(code.tax_rule_keys).to match_array([ "primary:sst_tax", "primary:tourism_tax", "hotel_tax:#{service_charge.id}", "hotel_tax:#{inactive_fee.id}" ])
    end

    it "does not update tax rules when the transaction code is invalid" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")

      patch hotel_transaction_code_path(hotel, code), params: {
        transaction_code: {
          code: "",
          name: "Parking Revenue",
          kind: "charge",
          category: "parking",
          active: "1",
          is_taxable: "1",
          tax_rule_keys: [ "primary:sst_tax", "hotel_tax:#{service_charge.id}" ]
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(code.reload.taxes).to be_empty
      expect(code.tax_rule_keys).to be_empty
    end

    it "clears taxable state and tax rules when saving an existing tax code" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
      code.update!(is_taxable: true, taxes: [ service_charge ])
      code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

      patch hotel_transaction_code_path(hotel, code), params: {
        transaction_code: {
          code: "TAX_SST",
          name: "SST",
          kind: "tax",
          category: "tax",
          active: "1",
          is_taxable: "1",
          tax_rule_keys: [ "primary:sst_tax", "hotel_tax:#{service_charge.id}", "hotel_tax:#{inactive_fee.id}" ]
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "default_codes"))
      expect(code.reload).not_to be_is_taxable
      expect(code.taxes).to be_empty
      expect(code.tax_rule_keys).to be_empty
    end

    it "prevents non-tax transaction codes from being updated into tax codes" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "parking_revenue")

      patch hotel_transaction_code_path(hotel, code), params: {
        transaction_code: {
          code: "PARKING",
          name: "Parking Revenue",
          kind: "tax",
          category: "tax",
          active: "1",
          is_taxable: "1"
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "default_codes"))
      expect(code.reload.kind).to eq("charge")
      expect(code.category).to eq("other")
    end

    it "prevents existing tax transaction codes from being updated into non-tax codes" do
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "sst_tax")

      patch hotel_transaction_code_path(hotel, code), params: {
        transaction_code: {
          code: "TAX_SST",
          name: "SST",
          kind: "charge",
          category: "other",
          active: "1",
          is_taxable: "1"
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "default_codes"))
      expect(code.reload.kind).to eq("tax")
      expect(code.category).to eq("tax")
      expect(code).not_to be_is_taxable
    end

    it "refreshes open folio forecasts when ROOM tax rules change under the open folio policy" do
      hotel.transaction_configuration.update!(room_revenue_tax_rule_application: "open_folio_forecasts")
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      allow(Folios::RefreshOpenForecastsFromRoomRevenueRules).to receive(:call)

      patch hotel_transaction_code_path(hotel, code), params: {
        transaction_code: {
          code: "ROOM",
          name: "Room Revenue",
          kind: "charge",
          category: "accommodation",
          active: "1",
          gl_account_code: "4010",
          is_taxable: "1",
          tax_rule_keys: [ "primary:sst_tax" ]
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "default_codes"))
      expect(Folios::RefreshOpenForecastsFromRoomRevenueRules).to have_received(:call).with(hotel: hotel, actor: user)
    end
  end

  describe "POST /hotel/:hotel_id/transaction-codes" do
    it "creates an additional transaction code preset" do
      expect {
        post hotel_transaction_codes_path(hotel), params: {
          transaction_code: {
            code: "SPA",
            name: "Spa Package",
            kind: "charge",
            category: "other",
            active: "1",
            gl_account_code: "4092",
            is_taxable: "1",
            tax_rule_keys: [ "primary:sst_tax", "hotel_tax:#{service_charge.id}" ]
          }
        }
      }.to change { hotel.transaction_codes.where(system_required: false, kind: "charge").count }.by(1)

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "additional_service_codes"))
      code = hotel.transaction_codes.find_by!(code: "SPA")
      expect(code.system_key).to eq("custom_spa")
      expect(code.taxes).to contain_exactly(service_charge)
      expect(code.tax_rule_keys).to match_array([ "primary:sst_tax", "hotel_tax:#{service_charge.id}" ])
    end

    it "prevents additional transaction codes from being created as tax codes" do
      post hotel_transaction_codes_path(hotel), params: {
        transaction_code: {
          code: "CITY_TAX",
          name: "City Tax",
          kind: "tax",
          category: "tax",
          active: "1",
          gl_account_code: "2010",
          is_taxable: "1"
        }
      }

      expect(response).to redirect_to(hotel_transaction_codes_path(hotel, tab: "additional_service_codes"))
      code = hotel.transaction_codes.find_by!(code: "CITY_TAX")
      expect(code.kind).to eq("charge")
      expect(code.category).to eq("other")
    end
  end
end
