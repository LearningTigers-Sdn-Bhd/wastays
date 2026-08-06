require "rails_helper"

RSpec.describe "HotelPortal::InHouseGuests", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_as(user)
  end

  it "redirects with only mapped front desk parameters" do
    get hotel_in_house_guests_path(hotel), params: { query: "Aisha", room_assignment: "assigned", page: 2, ignored: "x" }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "in_house", view: "list", in_house_query: "Aisha", room_assignment: "assigned", in_house_page: 2))
  end
end
