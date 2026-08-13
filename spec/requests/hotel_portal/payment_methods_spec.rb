require "rails_helper"

RSpec.describe "HotelPortal::PaymentMethods", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "live") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "renders the default registry" do
    get hotel_payment_methods_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Payment Methods Registry", "Cash Payment", "Bank Transfer Payment")
  end

  it "creates a payment method and its normalized code" do
    expect {
      post hotel_payment_methods_path(hotel), params: {
        hotel_payment_method: {
          name: "DuitNow QR", code: "duit-now", payment_method_type: "bank_gateway",
          guest_advance: "0", default_cash: "0", active: "1", surcharge_enabled: "0"
        }
      }
    }.to change(HotelPaymentMethod, :count).by(1).and change(TransactionCode, :count).by(1)

    method = hotel.hotel_payment_methods.order(:id).last
    expect(method.transaction_code).to have_attributes(code: "DUIT_NOW", category: "gateway_payment", kind: "payment")
  end

  it "points the code reference at Payment Methods for codes it owns" do
    PaymentMethods::EnsureDefaults.call(hotel)
    method = hotel.hotel_payment_methods.first

    get hotel_transaction_code_references_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(edit_hotel_payment_method_path(hotel, method))
  end

  it "locks availability in the edit sheet for the default cash method" do
    PaymentMethods::EnsureDefaults.call(hotel)
    payment_method = hotel.hotel_payment_methods.find_by!(default_cash: true)

    get edit_hotel_payment_method_path(hotel, payment_method)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Always active", "Choose another default cash method before deactivating this option.")
    expect(response.body).to include("No active Extra Charges")
    expect(response.body).not_to include('name="hotel_payment_method[active]"')
  end

  it "preserves default cash availability when the locked field is omitted" do
    PaymentMethods::EnsureDefaults.call(hotel)
    payment_method = hotel.hotel_payment_methods.find_by!(default_cash: true)

    patch hotel_payment_method_path(hotel, payment_method), params: {
      hotel_payment_method: {
        name: payment_method.name, code: payment_method.code, payment_method_type: "cash",
        guest_advance: "0", default_cash: "1", surcharge_enabled: "0"
      }
    }

    expect(response).to have_http_status(:redirect)
    expect(payment_method.transaction_code.reload).to be_active
  end

  it "rejects a forged attempt to deactivate the default cash method through update" do
    PaymentMethods::EnsureDefaults.call(hotel)
    payment_method = hotel.hotel_payment_methods.find_by!(default_cash: true)

    patch hotel_payment_method_path(hotel, payment_method), params: {
      hotel_payment_method: {
        name: payment_method.name, code: payment_method.code, payment_method_type: "cash",
        guest_advance: "0", default_cash: "1", active: "0", surcharge_enabled: "0"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Default cash must remain active")
    expect(payment_method.transaction_code.reload).to be_active
  end
end
