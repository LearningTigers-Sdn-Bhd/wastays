require 'rails_helper'

RSpec.describe HousekeepingRequest, type: :model do
  describe 'status helpers' do
    let(:request) { HousekeepingRequest.new }

    it 'correctly identifies completed status' do
      request.status = 'completed'
      expect(request.completed?).to be true
      expect(request.pending?).to be false
    end

    it 'correctly identifies pending status' do
      request.status = 'pending'
      expect(request.pending?).to be true
      expect(request.completed?).to be false
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
end
