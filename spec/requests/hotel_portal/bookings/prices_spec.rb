# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Prices", type: :request do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { room_type.standard_rate_plan }
  let(:check_in) { Date.current + 1.day }
  let(:check_out) { Date.current + 3.days }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  def grant_permission(slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  before do
    (check_in...check_out).each { |date| create(:room_rate, room_type: room_type, date: date, price: 100.0) }
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    grant_permission("view_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def price_params(extra = {})
    { room_type_id: room_type.id, rate_plan_id: rate_plan.id, check_in: check_in.iso8601, check_out: check_out.iso8601 }.merge(extra)
  end

  it "quotes the rate plan's own price when no total is typed" do
    get stay_price_hotel_bookings_path(hotel), params: price_params

    json = response.parsed_body
    expect(json["total_amount"].to_f).to eq(json["room_total"].to_f + json["tax_total"].to_f)
    expect(json["manual_rate_override"]).to be_nil
  end

  it "ignores a typed total from staff without the pricing permission" do
    get stay_price_hotel_bookings_path(hotel), params: price_params(target_total: "500.00")

    json = response.parsed_body
    expect(json["manual_rate_override"]).to be_nil
    expect(json["total_amount"].to_f).not_to eq(500.00)
  end

  context "with the pricing permission" do
    before { grant_permission("override_booking_rate") }

    it "backs the room net and tax out of a typed final total" do
      get stay_price_hotel_bookings_path(hotel), params: price_params(target_total: "500.00")

      json = response.parsed_body
      expect(json["total_amount"].to_f).to eq(500.00)
      expect(json["manual_rate_override"]).to be_present
      expect(json["manual_rate_override"].to_f + json["tax_total"].to_f).to eq(500.00)
    end
  end

  it "quotes an existing hand-priced booking's new dates at its own nightly rate" do
    booking = create(:booking, hotel: hotel, manual_rate_override: 196,
      check_in: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: check_in, kind: :check_in),
      check_out: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: check_out, kind: :check_out))
    create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan, subtotal: 196)

    get stay_price_hotel_bookings_path(hotel),
      params: price_params(check_out: (check_out + 1.day).iso8601, booking_id: booking.id)

    json = response.parsed_body
    expect(json["room_total"].to_d).to eq(294)
    expect(json["total_amount"].to_d).to eq(317.52.to_d)
  end

  it "quotes a shortened hand-priced stay for the nights it keeps" do
    booking = create(:booking, hotel: hotel, manual_rate_override: 196,
      check_in: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: check_in, kind: :check_in),
      check_out: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: check_out, kind: :check_out))
    create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan, subtotal: 196)

    get stay_price_hotel_bookings_path(hotel),
      params: price_params(check_out: (check_out - 1.day).iso8601, booking_id: booking.id)

    expect(response.parsed_body["room_total"].to_d).to eq(98)
  end
end
