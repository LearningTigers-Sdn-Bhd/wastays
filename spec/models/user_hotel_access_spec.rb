require 'rails_helper'

RSpec.describe UserHotelAccess, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:hotel) }
    it { should belong_to(:role) }
  end

  describe 'validations' do
    subject { create(:user_hotel_access) }
    it { should validate_uniqueness_of(:user_id).scoped_to(:hotel_id) }
  end
end
