require 'rails_helper'

RSpec.describe ChannelMapping, type: :model do
  describe 'associations' do
    it { should belong_to(:mappable) }
  end

  describe 'validations' do
    subject { create(:channel_mapping) }

    it { should validate_presence_of(:provider) }
    it { should validate_presence_of(:external_id) }

    it { should validate_uniqueness_of(:provider).scoped_to([ :mappable_type, :mappable_id ]) }
    it { should validate_uniqueness_of(:external_id).scoped_to(:provider) }
  end
end
