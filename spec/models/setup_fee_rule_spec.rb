require "rails_helper"

RSpec.describe SetupFeeRule, type: :model do
  let(:hotel) { create(:hotel, status: "live") }

  describe "validations" do
    it "accepts a valid global default" do
      setup_fee_rule = build(:setup_fee_rule, :global_default)

      expect(setup_fee_rule).to be_valid
    end

    it "accepts a valid hotel override" do
      setup_fee_rule = build(:setup_fee_rule, hotel: hotel)

      expect(setup_fee_rule).to be_valid
    end

    it "rejects a non-hotel target" do
      room_type = create(:room_type, hotel: hotel)
      setup_fee_rule = build(:setup_fee_rule, settable: room_type)

      expect(setup_fee_rule).not_to be_valid
      expect(setup_fee_rule.errors[:settable_type]).to include("must be blank or Hotel")
    end

    it "rejects a duplicate active global default" do
      create(:setup_fee_rule, :global_default)
      duplicate = build(:setup_fee_rule, :global_default)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include("Only one active global default setup fee is allowed.")
    end

    it "rejects a duplicate active hotel override for the same hotel" do
      create(:setup_fee_rule, hotel: hotel)
      duplicate = build(:setup_fee_rule, hotel: hotel)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include("Only one active setup fee override is allowed per hotel.")
    end

    it "requires amount to be greater than or equal to zero" do
      setup_fee_rule = build(:setup_fee_rule, :global_default, amount: -0.01)

      expect(setup_fee_rule).not_to be_valid
      expect(setup_fee_rule.errors[:amount]).to include("must be greater than or equal to 0")
    end
  end
end
