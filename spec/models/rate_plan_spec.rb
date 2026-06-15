require 'rails_helper'

RSpec.describe RatePlan, type: :model do
  describe 'associations' do
    it { should belong_to(:hotel) }
    it { should have_many(:room_type_rate_plans).dependent(:destroy) }
    it { should have_many(:room_types).through(:room_type_rate_plans) }
    it { should have_many(:room_rates).dependent(:destroy) }
    it { should have_one(:channel_mapping).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:sell_mode) }
    it { should validate_inclusion_of(:sell_mode).in_array(%w[per_room per_person]) }
    it { should validate_presence_of(:currency) }
  end
end
