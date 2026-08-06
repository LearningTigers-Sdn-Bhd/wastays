require 'rails_helper'

RSpec.describe "HotelPortal::GeneralLedgerMaps", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account, password: "password123") }
  let!(:gl_map) { hotel.hotel_general_ledger_maps.first } # Auto-created by callback

  before do
    # Ensure permission exists and is assigned
    perm = Permission.find_or_create_by!(slug: "manage_general_ledger_maps") { |p| p.name = "Manage GL Maps" }
    role = Role.find_or_create_by!(account: hotel.account, slug: "hotel_owner") do |r|
      r.name = "Hotel Owner"
    end
    RolePermission.find_or_create_by!(role: role, permission: perm)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)

    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get hotel_general_ledger_maps_path(hotel)
      expect(response).to have_http_status(:success)
    end

    it "backfills missing default General Ledger (GL) mappings for existing hotels" do
      hotel.hotel_general_ledger_maps.find_by!(transaction_category: "write_off").destroy!

      expect {
        get hotel_general_ledger_maps_path(hotel)
      }.to change { hotel.hotel_general_ledger_maps.where(transaction_category: "write_off").count }.from(0).to(1)

      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get edit_hotel_general_ledger_map_path(hotel, gl_map)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /update" do
    it "updates the gl map and redirects" do
      patch hotel_general_ledger_map_path(hotel, gl_map), params: {
        hotel_general_ledger_map: { gl_code: "NEW-CODE", description: "Updated desc" }
      }
      expect(response).to redirect_to(hotel_general_ledger_maps_path(hotel))
      expect(gl_map.reload.gl_code).to eq("NEW-CODE")
    end
  end
end
