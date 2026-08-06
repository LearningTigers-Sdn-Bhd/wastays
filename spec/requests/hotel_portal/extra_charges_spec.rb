require "rails_helper"

RSpec.describe "HotelPortal::ExtraCharges", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders a Commercial registry with default and custom extra charges" do
    custom = create(:hotel_extra_charge, hotel: hotel)

    get hotel_extra_charges_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Extra Charges Registry", custom.name, "Food &amp; Beverage")
    expect(response.body).to include("settings/commercial/extra-charges")
  end

  it "renders the create sheet without transaction-code internals" do
    get new_hotel_extra_charge_path(hotel), headers: { "Turbo-Frame" => "settings_action_sheet" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Extra Charge", "Pricing method", "Taxes applied to this charge")
    expect(response.body).not_to include("System key", "GL Account")
  end

  it "creates the registry item and normalized transaction code atomically" do
    expect {
      post hotel_extra_charges_path(hotel), params: {
        hotel_extra_charge: {
          name: "Airport Transfer", code: "airport", description: "One-way transfer", category: "other",
          pricing_type: "fixed", rate_value: "80", charging_unit: "per_item",
          allow_amount_override: "0", active: "1", tax_rule_keys: []
        }
      }
    }.to change(HotelExtraCharge, :count).by(1).and change(TransactionCode, :count).by(1)

    extra_charge = hotel.hotel_extra_charges.order(:id).last
    expect(extra_charge.transaction_code).to have_attributes(
      name: "Airport Transfer", code: "AIRPORT", kind: "charge", category: "other",
      system_required: false, active: true
    )
    expect(extra_charge).to have_attributes(pricing_type: "fixed", rate_value: 80.to_d)
  end

  it "rejects codes longer than ten characters without truncating them" do
    expect {
      post hotel_extra_charges_path(hotel), params: {
        hotel_extra_charge: {
          name: "Airport Transfer", code: "AIRPORTBUS2", category: "other",
          pricing_type: "manual", charging_unit: "per_item", active: "1"
        }
      }
    }.not_to change(HotelExtraCharge, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Code must be 10 characters or fewer")
  end

  it "updates status on the backing transaction code" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel)

    patch status_hotel_extra_charge_path(hotel, extra_charge), params: { active: "0" }

    expect(response).to redirect_to(hotel_extra_charges_path(hotel))
    expect(extra_charge.transaction_code.reload).not_to be_active
  end
end
