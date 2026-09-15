# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel Portal operational dates", type: :request do
  let(:account) { create(:account) }
  let(:hotel) do
    create(
      :hotel,
      :without_current_business_date,
      account: account,
      status: "live",
      time_zone: "Kuala Lumpur"
    )
  end
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "returns the persisted Working Date and hotel-local System Date" do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.new(2026, 9, 14))

    travel_to(Time.utc(2026, 9, 14, 16, 30)) do
      get hotel_operational_dates_path(hotel), headers: { "Accept" => "application/json" }
    end

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body).to eq(
      "working_date" => { "value" => "2026-09-14", "label" => "14 Sep 2026" },
      "system_date" => { "value" => "2026-09-15", "label" => "15 Sep 2026" }
    )
  end

  it "returns an unavailable Working Date without creating one" do
    expect {
      get hotel_operational_dates_path(hotel), headers: { "Accept" => "application/json" }
    }.not_to change(HotelBusinessDate, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("working_date")).to eq(
      "value" => nil,
      "label" => "Unavailable"
    )
  end

  it "requires an authenticated hotel user" do
    delete logout_path

    get hotel_operational_dates_path(hotel), headers: { "Accept" => "application/json" }

    expect(response).to redirect_to(login_path)
  end

  it "does not expose a hotel outside the user's access" do
    other_hotel = create(:hotel, account: create(:account), status: "live")

    get hotel_operational_dates_path(other_hotel), headers: { "Accept" => "application/json" }

    expect(response).not_to have_http_status(:ok)
  end
end
