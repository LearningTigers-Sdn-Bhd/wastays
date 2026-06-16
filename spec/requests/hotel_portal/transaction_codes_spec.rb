require "rails_helper"

RSpec.describe "HotelPortal::TransactionCodes", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered") }
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

  describe "GET /hotel/:hotel_id/transaction-codes" do
    it "renders the transaction codes page with placeholder code tabs" do
      get hotel_transaction_codes_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Transaction Codes")
      expect(response.body).to include("Configure transaction codes used when posting charges, refunds, payments, and adjustments to guest folios.")
      expect(response.body).to include("Default Codes")
      expect(response.body).to include("Additional Service Codes")
      expect(response.body).to include("Default transaction code setup is coming soon.")
      expect(response.body).to include("Additional service code setup is coming soon.")
      expect(response.body).not_to include("Tax Listing")
    end
  end
end
