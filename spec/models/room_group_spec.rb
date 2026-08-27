# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoomGroup, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:hotel) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    describe "uniqueness" do
      let(:hotel) { create(:hotel) }
      subject { build(:room_group, hotel: hotel) }

      it { is_expected.to validate_uniqueness_of(:name).scoped_to(:hotel_id) }
    end
  end
end
