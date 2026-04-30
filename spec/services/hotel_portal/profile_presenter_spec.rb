# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HotelPortal::ProfilePresenter do
  let(:hotel) { create(:hotel) }
  let(:queue_service) { instance_double(HotelPortal::PhotoQueueService, queued_photo_signed_ids: [], queued_count: 0, remaining_slots: 20) }
  let(:context) { double('view_context') }
  let(:presenter) { described_class.new(hotel, queue_service, context) }

  describe '#setup_fee_source' do
    it 'delegates to hotel' do
      expect(hotel).to receive(:setup_fee_source).and_return("Global Default")
      expect(presenter.setup_fee_source).to eq("Global Default")
    end
  end

  describe '#queue_summary' do
    it 'returns summary hash' do
      summary = presenter.queue_summary
      expect(summary).to have_key(:queued_count)
      expect(summary).to have_key(:existing_count)
      expect(summary).to have_key(:max_count)
      expect(summary).to have_key(:remaining_slots)
    end
  end
end
