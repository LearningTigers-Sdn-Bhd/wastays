# frozen_string_literal: true

require "rails_helper"

RSpec.describe "hotel factory" do
  it "creates exactly one production-derived current accounting date by default" do
    hotel = create(:hotel)

    expect(hotel.hotel_business_dates.current.count).to eq(1)
    expect(hotel.current_business_date).to eq(hotel.business_date_for(Time.current))
  end

  it "supports an explicit accounting business date" do
    date = Date.new(2025, 1, 15)

    hotel = create(:hotel, accounting_business_date: date)

    expect(hotel.current_business_date).to eq(date)
    expect(hotel.hotel_business_dates.current.count).to eq(1)
  end

  it "supports an explicit hotel without a current accounting date" do
    hotel = create(:hotel, :without_current_business_date)

    expect(hotel.hotel_business_dates.current).to be_empty
  end
end
