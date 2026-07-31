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

  describe 'work contexts' do
    it 'exposes predicates for each dispatch boundary' do
      expect(described_class.new(work_context: 'guest_request')).to be_guest_request
      expect(described_class.new(work_context: 'vacant_room_task')).to be_vacant_room_task
      expect(described_class.new(work_context: 'checkout_turnover')).to be_checkout_turnover
    end

    # A turnover stands on its own. Most guests never send a checkout request --
    # they walk to the desk -- so requiring one would make the common departure
    # the invalid case.
    it 'accepts turnover work with no checkout request behind it' do
      expect(build(:housekeeping_request, work_context: 'checkout_turnover')).to be_valid
    end

    it 'refuses a context it does not have' do
      expect(build(:housekeeping_request, work_context: 'something_else')).not_to be_valid
    end
  end
end
