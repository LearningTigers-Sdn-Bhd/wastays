require 'rails_helper'

RSpec.describe BookingNote, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:booking) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:body) }
  end
end
