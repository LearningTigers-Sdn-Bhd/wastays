# frozen_string_literal: true

require "rails_helper"

RSpec.describe BusinessDates::ResetAuthority do
  it "replaces all rows with one requested current accounting date" do
    hotel = create(:hotel)
    date = Date.new(2025, 1, 15)

    replacement = described_class.call!(hotel: hotel, date: date)

    expect(hotel.hotel_business_dates.reload).to contain_exactly(replacement)
    expect(replacement).to have_attributes(business_date: date, status: "open")
  end
end
