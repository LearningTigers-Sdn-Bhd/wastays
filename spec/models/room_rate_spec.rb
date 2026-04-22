require 'rails_helper'

RSpec.describe RoomRate, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:room_type) }
  end

  describe 'validations' do
    subject(:room_rate) { create(:room_rate) }

    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_presence_of(:price) }
    it { is_expected.to validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_uniqueness_of(:date).scoped_to(:room_type_id) }
  end
end
