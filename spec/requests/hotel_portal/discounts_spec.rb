require "rails_helper"

RSpec.describe "HotelPortal::Discounts", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "live") }
  let(:user) { create(:user, account:) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    role = create(:role, account:, permissions: [ permission ])
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders the registry and ensures the default Rebate" do
    get hotel_discounts_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Discounts Registry", "Rebate", "All eligible charges")
  end

  it "creates a selected-charge discount and normalized code" do
    charge_code = create(:transaction_code, hotel:, code: "SPA", name: "Spa")

    expect {
      post hotel_discounts_path(hotel), params: { hotel_discount: {
        name: "F&B Recovery", code: "fnb disc", pricing_type: "percentage", rate_value: "10",
        application_scope: "selected_charges", allow_amount_override: "1", active: "1",
        applicable_transaction_code_ids: [ charge_code.id ]
      } }
    }.to change(HotelDiscount, :count).by(1).and change(TransactionCode, :count).by(1)

    discount = hotel.hotel_discounts.order(:id).last
    expect(discount.transaction_code).to have_attributes(code: "FNB_DISC", kind: "adjustment", category: "discount")
    expect(discount).not_to be_allow_amount_override
    expect(discount.applicable_transaction_codes).to contain_exactly(charge_code)
  end

  it "deactivates the backing code" do
    discount = create(:hotel_discount, hotel:)

    patch status_hotel_discount_path(hotel, discount), params: { active: "0" }

    expect(response).to redirect_to(hotel_discounts_path(hotel))
    expect(discount.transaction_code.reload).not_to be_active
  end

  it "rejects selected charge codes from another hotel" do
    foreign_code = create(:transaction_code)

    expect {
      post hotel_discounts_path(hotel), params: { hotel_discount: {
        name: "Foreign", code: "FOREIGN", pricing_type: "manual", application_scope: "selected_charges",
        active: "1", applicable_transaction_code_ids: [ foreign_code.id ]
      } }
    }.not_to change(HotelDiscount, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("unavailable charge code")
  end

  it "keeps existing selected codes when an update is invalid" do
    original_code = create(:transaction_code, hotel:, code: "SPA")
    discount = create(:hotel_discount, hotel:, application_scope: "selected_charges",
      applicable_transaction_codes: [ original_code ])
    foreign_code = create(:transaction_code)

    patch hotel_discount_path(hotel, discount), params: { hotel_discount: {
      name: discount.name, code: discount.code, pricing_type: "manual", application_scope: "selected_charges",
      active: "1", applicable_transaction_code_ids: [ foreign_code.id ]
    } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(discount.reload.applicable_transaction_codes).to contain_exactly(original_code)
  end
end
