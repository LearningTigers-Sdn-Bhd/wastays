require 'rails_helper'

RSpec.describe HotelGeneralLedgerMap, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
  end

  describe 'validations' do
    subject { build(:hotel_general_ledger_map) }

    it { is_expected.to validate_presence_of(:transaction_category) }
    it { is_expected.to validate_presence_of(:gl_code) }

    it 'validates inclusion of transaction_category in allowed categories' do
      FolioTransaction.gl_mappable_categories.each do |valid_category|
        map = build(:hotel_general_ledger_map, hotel: build(:hotel), transaction_category: valid_category)
        expect(map).to be_valid
      end

      invalid_category = 'non_existent_category'
      map = build(:hotel_general_ledger_map, transaction_category: invalid_category)
      expect(map).not_to be_valid
      expect(map.errors[:transaction_category]).to include("#{invalid_category} is not a valid transaction category")
    end

    it 'validates uniqueness of transaction_category scoped to hotel' do
      hotel = create(:hotel)
      # The callback already created the 'accommodation' map
      duplicate = build(:hotel_general_ledger_map, hotel: hotel, transaction_category: 'accommodation')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:transaction_category]).to include('has already been taken')
    end
  end
end
