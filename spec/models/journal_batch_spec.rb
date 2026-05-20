require 'rails_helper'

RSpec.describe JournalBatch, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to have_many(:entries).class_name('JournalBatchEntry').dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:business_date) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates uniqueness of business_date scoped to hotel' do
      hotel = create(:hotel)
      create(:journal_batch, hotel: hotel, business_date: Date.current)
      duplicate = build(:journal_batch, hotel: hotel, business_date: Date.current)
      expect(duplicate).not_to be_valid
    end
  end
end
