require 'rails_helper'

RSpec.describe ComplaintRequest, type: :model do
  describe 'status helpers' do
    let(:request) { ComplaintRequest.new }

    it 'correctly identifies resolved status' do
      request.status = 'resolved'
      expect(request.resolved?).to be true
      expect(request.pending?).to be false
    end

    it 'correctly identifies pending status' do
      request.status = 'pending'
      expect(request.pending?).to be true
      expect(request.resolved?).to be false
    end

    it 'correctly identifies in_progress status' do
      request.status = 'in_progress'
      expect(request.in_progress?).to be true
    end

    it 'correctly identifies failed status' do
      request.status = 'failed'
      expect(request.failed?).to be true
    end
  end

  describe '#resolved!' do
    let(:request) { ComplaintRequest.new(status: 'pending') }

    it 'sets status to resolved and sets completed_at' do
      expect { request.resolved! }.to change { request.status }.to('resolved')
                                  .and change { request.completed_at }.from(nil)
    end

    it 'does not overwrite existing completed_at' do
      completed_at = 1.hour.ago
      request.completed_at = completed_at
      request.resolved!
      expect(request.completed_at).to be_within(1.second).of(completed_at)
    end
  end

  describe '#reopen!' do
    let(:request) { ComplaintRequest.new(status: 'resolved', completed_at: Time.current) }

    it 'sets status to in_progress and clears completed_at' do
      expect { request.reopen! }.to change { request.status }.to('in_progress')
                                .and change { request.completed_at }.to(nil)
    end
  end
end
