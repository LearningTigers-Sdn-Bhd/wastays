require "rails_helper"
require "securerandom"

RSpec.describe "Admin::ApiKeys", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin API #{token}") }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-api-#{token}@example.com") }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /admin/api_keys" do
    def displayed_names
      Nokogiri::HTML(response.body).css("tbody tr td:first-child:not([colspan])").map(&:text).map(&:strip)
    end

    it "uses stable 25-row pages and ignores requested limit overrides" do
      created_at = Time.current.change(usec: 0)
      keys = Array.new(51) { |index| create(:api_key, bearer: nil, name: "Pagination key #{index}", created_at: created_at) }
      ordered_names = keys.reverse.map(&:name)

      [ [ 1, ordered_names.first(25) ], [ 2, ordered_names.slice(25, 25) ], [ 3, ordered_names.last(1) ] ].each do |number, names|
        get admin_api_keys_path, params: { page: number, limit: 1000, per_page: 1000 }

        expect(response).to have_http_status(:ok)
        expect(displayed_names).to eq(names)
        expect(response.body).to include("panel-pagination")
      end

      get admin_api_keys_path, params: { page: 99 }
      expect(response).to have_http_status(:ok)
      expect(displayed_names).to be_empty
    end

    it "normalizes missing, invalid, zero, negative, and structured pages to the first page" do
      key = create(:api_key, bearer: nil, name: "Visible first-page key")

      [ nil, "invalid", "2junk", "0", "-1", [ "2" ], { number: "2" } ].each do |value|
        get admin_api_keys_path, params: { page: value }

        expect(response).to have_http_status(:ok)
        expect(displayed_names).to eq([ key.name ])
      end
    end

    it "renders the disabled navigation for an empty list" do
      get admin_api_keys_path

      expect(response).to have_http_status(:ok)
      navigation = Nokogiri::HTML(response.body).at_css("nav.panel-pagination")
      expect(navigation.css("a")).to be_empty
      expect(navigation.at_css('[aria-current="page"]').text).to eq("1")
    end

    it "does not allow a non-superadmin to view the index" do
      user = create(:user, :admin)
      hotel = create(:hotel, account: user.account, status: "live")
      role = create(:role, account: user.account, slug: "hotel_owner", name: "Hotel Owner")
      UserHotelAccess.create!(user: user, hotel: hotel, role: role)
      delete logout_path
      sign_in_as(user)
      get admin_api_keys_path

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /admin/api_keys" do
    let(:params) do
      {
        api_key: {
          name: "Primary Integration Key",
          bearer_type: "",
          bearer_id: ""
        }
      }
    end

    it "reveals the generated token in a one-time modal on index" do
      post admin_api_keys_path, params: params

      expect(response).to redirect_to(admin_api_keys_path)
      follow_redirect!

      generated_key = ApiKey.order(:created_at).last
      expect(response.body).to include("API Key Created")
      expect(response.body).to include("This API key is shown only once")
      expect(response.body).to include(generated_key.token)
      expect(response.body).not_to include("API Key created:")
    end

    it "does not show the reveal modal again after the first page load" do
      post admin_api_keys_path, params: params
      follow_redirect!

      get admin_api_keys_path

      expect(response.body).not_to include("API Key Created")
      expect(response.body).not_to include("This API key is shown only once")
    end
  end
end
