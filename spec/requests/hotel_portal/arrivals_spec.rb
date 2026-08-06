require "rails_helper"

RSpec.describe "HotelPortal::Arrivals", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user:, hotel:, role:)
    sign_in_as(user)
  end

  it "redirects with only mapped front desk parameters before arrival authorization" do
    get hotel_arrivals_path(hotel), params: { date: "2026-07-15", q: "Aisha", page: 2, ignored: "x" }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "arrivals", view: "list", arrival_date: "2026-07-15", arrival_q: "Aisha", arrival_page: 2))
  end

  it "logs out users whose account has been suspended" do
    user.account.update!(status: "suspended")

    get hotel_arrivals_path(hotel)

    expect(response).to redirect_to(login_path)
  end
end
