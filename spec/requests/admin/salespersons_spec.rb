require "rails_helper"
require "securerandom"

RSpec.describe "Admin::Salespersons", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Salespersons #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-salespersons-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /admin/salespersons" do
    let!(:matched_salesperson) do
      create(
        :user,
        account: admin_account,
        role: "salesperson",
        name: "Mira Tan #{token}",
        email: "mira-#{token}@example.com"
      )
    end
    let!(:matched_hotel) do
      create(:hotel, account: admin_account, name: "Luma Stay #{token}", city: "Kuala Lumpur", salesperson: matched_salesperson)
    end
    let!(:other_salesperson) do
      create(
        :user,
        account: admin_account,
        role: "salesperson",
        name: "Farid Osman #{token}",
        email: "farid-#{token}@example.com"
      )
    end
    let!(:other_hotel) do
      create(:hotel, account: admin_account, name: "Ocean Breeze #{token}", city: "Penang", salesperson: other_salesperson)
    end

    it "renders the salesperson management page with the live search controls" do
      get admin_salespersons_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Salespersons")
      expect(response.body).to include('placeholder="Search name, email, or hotel..."')
      expect(response.body).to include('data-controller="live-filter"')
      expect(response.body).to include("Mira Tan #{token.capitalize}")
      expect(response.body).to include("mira-#{token}@example.com")
      expect(response.body).to include("Luma Stay #{token}")
      expect(response.body).to include("Farid Osman #{token.capitalize}")
      expect(response.body).to include("Ocean Breeze #{token}")
    end

    it "filters salespersons by matching hotel name" do
      get admin_salespersons_path(query: "Luma Stay #{token}")

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      names = doc.css('#salespersons_results [data-salesperson-inline-edit-target="nameDisplay"]').map(&:text).map(&:strip)

      expect(names).to include("Mira Tan #{token.capitalize}")
      expect(names).not_to include("Farid Osman #{token.capitalize}")
    end

    it "filters salespersons by matching email" do
      get admin_salespersons_path(query: "farid-#{token}@example.com")

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      names = doc.css('#salespersons_results [data-salesperson-inline-edit-target="nameDisplay"]').map(&:text).map(&:strip)

      expect(names).to include("Farid Osman #{token.capitalize}")
      expect(names).not_to include("Mira Tan #{token.capitalize}")
    end
  end

  describe "POST /admin/salespersons" do
    let!(:assigned_hotel) do
      create(:hotel, account: admin_account, name: "Assigned Hotel #{token}", city: "Kuala Lumpur")
    end

    it "creates a salesperson and assigns selected hotels" do
      expect do
        post admin_salespersons_path, params: {
          user: {
            name: "New Salesperson #{token}",
            email: "new-salesperson-#{token}@example.com"
          },
          hotel_ids: [ assigned_hotel.id ]
        }
      end.to change(User, :count).by(1)

      salesperson = User.find_by!(email: "new-salesperson-#{token}@example.com")

      expect(response).to redirect_to(admin_salespersons_path)
      expect(salesperson.role).to eq("salesperson")
      expect(salesperson.account).to eq(admin_account)
      expect(assigned_hotel.reload.salesperson).to eq(salesperson)
    end
  end
end
