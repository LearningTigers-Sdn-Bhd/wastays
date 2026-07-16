require "rails_helper"

RSpec.describe "HotelPortal::TaxesFees", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered", tourism_tax_enabled: false, tourism_tax_amount: 10.0, sst_enabled: false) }
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

  describe "GET /hotel/:hotel_id/taxes-fees" do
    it "renders the canonical taxes and fees page" do
      get hotel_taxes_fees_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.css("h1").map { |heading| heading.text.squish }).to eq([ "Taxes & Fees" ])
      expect(response.body).to include("Primary Tax Settings")
      expect(response.body).to include("Additional Taxes &amp; Fees")
      expect(response.body).to include(%(data-testid="settings-tabs"))
    end

    it "renders the table-based tax and fees panel without transaction code tabs" do
      get hotel_taxes_fees_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Taxes &amp; Fees")
      expect(response.body).to include("Primary Tax Settings")
      expect(response.body).to include("Additional Taxes &amp; Fees")
      expect(response.body).to include("Malaysia Hotel Tax Reference Table")
      expect(response.body).not_to include("Tax Configuration")
      expect(response.body).not_to include("Custom Taxes")
      expect(response.body).not_to include("Add New Tax")
      expect(response.body).not_to include("Default Transaction Code")
      expect(response.body).not_to include("Extra Transaction Code")
      expect(response.body).not_to include("data-testid=\"taxes-transactions-tabs\"")
    end
  end

  describe "PATCH /hotel/:hotel_id/taxes-fees" do
    it "updates hotel tax settings" do
      patch hotel_taxes_fees_path(hotel), params: {
        form_id: "tax_settings",
        hotel: {
          tourism_tax_enabled: "1",
          tourism_tax_amount: "12.0",
          sst_enabled: "1"
        }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      follow_redirect!
      expect(response.body).to include("Tax settings updated successfully.")

      hotel.reload
      expect(hotel.tourism_tax_enabled?).to be(true)
      expect(hotel.tourism_tax_amount).to eq(12.0)
      expect(hotel.sst_enabled?).to be(true)
    end

    it "updates only the tourism tax amount from the inline edit form" do
      hotel.update!(tourism_tax_enabled: true, tourism_tax_amount: 10.0, sst_enabled: false)

      patch hotel_taxes_fees_path(hotel), params: {
        form_id: "tax_settings",
        hotel: {
          tourism_tax_amount: "15.50"
        }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      hotel.reload
      expect(hotel.tourism_tax_amount).to eq(15.5)
      expect(hotel.tourism_tax_enabled?).to be(true)
      expect(hotel.sst_enabled?).to be(false)
    end

    it "toggles primary tax statuses independently" do
      patch hotel_taxes_fees_path(hotel), params: {
        form_id: "tax_settings",
        hotel: {
          tourism_tax_enabled: "1"
        }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      expect(hotel.reload.tourism_tax_enabled?).to be(true)

      patch hotel_taxes_fees_path(hotel), params: {
        form_id: "tax_settings",
        hotel: {
          sst_enabled: "1"
        }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      expect(hotel.reload.sst_enabled?).to be(true)
    end

    it "renders the canonical taxes and fees page when tax update is invalid" do
      allow_any_instance_of(HotelPortal::TaxSettingsForm).to receive(:save).and_return(false)

      patch hotel_taxes_fees_path(hotel), params: {
        form_id: "tax_settings",
        hotel: {
          tourism_tax_amount: "12"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(data-testid="settings-tabs"))
      expect(response.body).to include(%(data-testid="taxes-fees-content"))
    end
  end

  describe "additional taxes and fees" do
    it "renders the add fee offcanvas" do
      hotel.update!(status: "approved")
      get new_hotel_hotel_tax_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("#hotel-settings-sidebar")).to be_present
      expect(response.parsed_body.at_css("#hotel-sidebar")).to be_nil
      expect(response.body).to include("turbo-frame id=\"offcanvas_drawer\"")
      expect(response.body).to include("Add Fee")
      expect(response.body).to include("Transaction Code")
      expect(response.body).to include("Charge Type")
      expect(response.body).to include("Amount Type")
      expect(response.body).to include("Fixed RM")
      expect(response.body).to include("Percentage")
    end

    it "renders the edit fee offcanvas" do
      tax = HotelTax.create!(hotel: hotel, name: "Heritage Fee", rate_type: "flat", amount: 2.0, enabled: false)

      get edit_hotel_hotel_tax_path(hotel, tax)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-frame id=\"offcanvas_drawer\"")
      expect(response.body).to include("Edit Fee")
      expect(response.body).to include("Heritage Fee")
    end

    it "returns custom tax mutations to the tax listing tab" do
      post hotel_hotel_taxes_path(hotel), params: {
        hotel_tax: {
          name: "Heritage Fee",
          code: "DBKK",
          charge_type: "tax",
          rate_type: "flat",
          amount: "5.00",
          enabled: "1"
        }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      tax = hotel.hotel_taxes.find_by!(name: "Heritage Fee")
      expect(tax.amount).to eq(5.0)
      expect(tax.charge_type).to eq("tax")
      expect(tax.code).to eq("DBKK")
      expect(tax.transaction_code.code).to eq("TAX_DBKK")
    end

    it "creates non-tax fee transaction codes without the tax prefix" do
      post hotel_hotel_taxes_path(hotel), params: {
        hotel_tax: {
          name: "Service Charge",
          code: "SC",
          charge_type: "charge",
          rate_type: "percentage",
          amount: "10.00",
          enabled: "1"
        }
      }

      expect(response).to redirect_to(hotel_taxes_fees_path(hotel))
      tax = hotel.hotel_taxes.find_by!(name: "Service Charge")
      expect(tax.transaction_code.code).to eq("SC")
      expect(tax.transaction_code.kind).to eq("charge")
    end

    it "renders the add fee offcanvas with errors when create is invalid" do
      post hotel_hotel_taxes_path(hotel), params: {
        hotel_tax: {
          name: "",
          code: "",
          charge_type: "tax",
          rate_type: "flat",
          amount: "5.00",
          enabled: "1"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Add Fee")
      expect(response.body).to include("Name can")
      expect(response.body).to include("be blank")
    end

    it "renders the edit fee offcanvas with errors when update is invalid" do
      tax = HotelTax.create!(hotel: hotel, name: "Heritage Fee", rate_type: "flat", amount: 2.0, enabled: true)

      patch hotel_hotel_tax_path(hotel, tax), params: {
        hotel_tax: {
          name: "Heritage Fee",
          code: "HF2",
          charge_type: "tax",
          rate_type: "flat",
          amount: "0",
          enabled: "1"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Edit Fee")
      expect(response.body).to include("Amount must be greater than 0")
    end
  end
end
