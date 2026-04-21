require 'rails_helper'

RSpec.describe PayoutBatch, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:hotel) }
    it { is_expected.to have_many(:bookings).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(PayoutBatch::STATUSES) }
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_numericality_of(:amount).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_presence_of(:period_start) }
    it { is_expected.to validate_presence_of(:period_end) }
  end

  describe 'scopes' do
    let!(:pending_batch) { create(:payout_batch, status: 'pending') }
    let!(:paid_batch) { create(:payout_batch, status: 'paid') }

    it 'filters by pending status' do
      expect(described_class.pending).to contain_exactly(pending_batch)
    end

    it 'filters by paid status' do
      expect(described_class.paid).to contain_exactly(paid_batch)
    end
  end

  describe '#paid?' do
    it 'returns true only for paid status' do
      expect(build(:payout_batch, status: 'paid').paid?).to be(true)
      expect(build(:payout_batch, status: 'pending').paid?).to be(false)
    end
  end
end
