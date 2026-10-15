# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hotel, "agent payment terms" do
  let(:hotel) { build(:hotel) }

  it "defaults to 50% within the hold and everything 30 days before arrival, deposit refundable" do
    expect(hotel).to have_attributes(
      agent_deposit_percentage: 50, agent_full_payment_days_before_arrival: 30, agent_deposit_non_refundable: false
    )
  end

  it "keeps the deposit between 1 and 100 percent" do
    [ 0, 101, -5 ].each do |value|
      hotel.agent_deposit_percentage = value
      hotel.validate
      expect(hotel.errors[:agent_deposit_percentage]).to be_present
    end
    [ 1, 100 ].each do |value|
      hotel.agent_deposit_percentage = value
      hotel.validate
      expect(hotel.errors[:agent_deposit_percentage]).to be_empty
    end
  end

  it "needs a whole, positive number of days before arrival" do
    [ 0, -1 ].each do |value|
      hotel.agent_full_payment_days_before_arrival = value
      hotel.validate
      expect(hotel.errors[:agent_full_payment_days_before_arrival]).to be_present
    end
  end
end
