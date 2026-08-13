require "rails_helper"

RSpec.describe "HotelPortal::CheckedOutGuests", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_as(user)
  end

  it "redirects with only mapped front desk parameters" do
    get hotel_checked_out_guests_path(hotel), params: { query: "Aisha", page: 2, ignored: "x" }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "checkout", view: "list", checkout_query: "Aisha", checkout_page: 2))
  end
end
