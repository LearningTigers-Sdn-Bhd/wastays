require 'rails_helper'

RSpec.describe RoomType, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to have_many(:room_rates).dependent(:destroy) }
    it { is_expected.to have_many(:room_inventories).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:max_adults) }
    it { is_expected.to validate_numericality_of(:max_adults).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:base_price) }
    it { is_expected.to validate_numericality_of(:base_price).is_greater_than_or_equal_to(0) }
  end
end
