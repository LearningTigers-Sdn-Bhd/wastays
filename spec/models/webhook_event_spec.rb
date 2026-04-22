require 'rails_helper'

RSpec.describe WebhookEvent, type: :model do
  describe 'validations' do
    subject(:webhook_event) { create(:webhook_event) }

    it { is_expected.to validate_presence_of(:gateway) }
    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_uniqueness_of(:external_id).scoped_to(:gateway) }
  end

  describe 'scopes' do
    let!(:failed_event) { create(:webhook_event, status: 'failed') }
    let!(:pending_event) { create(:webhook_event, status: 'pending') }

    it 'filters failed events' do
      expect(described_class.failed).to contain_exactly(failed_event)
    end

    it 'filters pending events' do
      expect(described_class.pending).to contain_exactly(pending_event)
    end
  end
end
