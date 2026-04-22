require 'rails_helper'

RSpec.describe PropertyPolicy, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:check_in_time) }
    it { is_expected.to validate_presence_of(:check_out_time) }
    it { is_expected.to validate_presence_of(:currency) }
    it { is_expected.to validate_presence_of(:usd_rate) }
  end
end
