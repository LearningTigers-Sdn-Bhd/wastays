require "rails_helper"

RSpec.describe Discounts::EnsureDefaults do
  it "registers the system Rebate once" do
    hotel = create(:hotel)

    expect { described_class.call(hotel) }.to change(HotelDiscount, :count).by(1)
    discount = hotel.hotel_discounts.first
    expect(discount.transaction_code.system_key).to eq("rebate")
    expect(discount).to have_attributes(pricing_type: "manual", application_scope: "all_eligible_charges")
    expect { described_class.call(hotel) }.not_to change(HotelDiscount, :count)
  end
end
