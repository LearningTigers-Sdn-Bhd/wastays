# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Room Status", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    create(:user_hotel_access, user: user, hotel: hotel)
    sign_in_as(user)
  end

  it "responds successfully for authenticated hotel staff" do
    get hotel_room_status_board_path(hotel)

    expect(response).to have_http_status(:success)
  end
end
