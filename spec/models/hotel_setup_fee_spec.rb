require "rails_helper"

RSpec.describe Hotel, "#effective_setup_fee" do
  let(:hotel) { create(:hotel, status: "approved") }

  it "returns the hotel override when one exists" do
    create(:setup_fee_rule, :global_default, amount: 500.0)
    create(:setup_fee_rule, hotel: hotel, amount: 1200.0)

    expect(hotel.effective_setup_fee).to eq(1200.0)
  end

  it "falls back to the global default when no hotel override exists" do
    create(:setup_fee_rule, :global_default, amount: 500.0)

    expect(hotel.effective_setup_fee).to eq(500.0)
  end

  it "returns zero when no setup fee rules exist" do
    expect(hotel.effective_setup_fee).to eq(0.0)
  end
end
