require 'rails_helper'

RSpec.describe Hotel, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:user_hotel_accesses).dependent(:destroy) }
    it { should have_many(:users).through(:user_hotel_accesses) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:city) }
    it { should validate_presence_of(:country) }
  end

  describe 'constants' do
    it 'defines allowed statuses' do
      expect(Hotel::STATUSES).to match_array(%w[
        registered
        email_verified
        profile_incomplete
        rooms_incomplete
        inventory_incomplete
        pending_review
        approved
        live
        suspended
      ])
    end
  end

  describe '#active?' do
    it 'returns true if status is approved' do
      hotel = build(:hotel, status: 'approved')
      expect(hotel.active?).to be true
    end

    it 'returns true if status is live' do
      hotel = build(:hotel, status: 'live')
      expect(hotel.active?).to be true
    end

    it 'returns false if status is registered' do
      hotel = build(:hotel, status: 'registered')
      expect(hotel.active?).to be false
    end
  end
end
