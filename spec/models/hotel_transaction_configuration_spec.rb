# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelTransactionConfiguration, type: :model do
  it { is_expected.to belong_to(:hotel) }

  it "allows only one configuration per hotel" do
    hotel = create(:hotel)
    create(:hotel_transaction_configuration, hotel: hotel)

    duplicate = build(:hotel_transaction_configuration, hotel: hotel)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:hotel_id]).to include("has already been taken")
  end

  it "defaults room revenue tax rule application to new bookings only" do
    configuration = described_class.create!(hotel: create(:hotel))

    expect(configuration.room_revenue_tax_rule_application).to eq("new_bookings_only")
    expect(configuration).to be_new_bookings_only
  end
end
