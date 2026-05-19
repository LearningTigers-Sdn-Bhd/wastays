require 'rails_helper'

RSpec.describe ChannelManagers::PullRevisionsJob, type: :job do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel, preferred_channel_manager: 'channex') }
  let(:client_double) { instance_double(Channex::Client) }

  before do
    clear_enqueued_jobs
    create(:channel_mapping, mappable: hotel, provider: 'channex', external_id: 'prop_1')
    allow(Channex::Client).to receive(:new).and_return(client_double)
  end

  it 'enqueues ingest job for mapped property revisions in feed' do
    allow(client_double).to receive(:get).with('/booking_revisions/feed', hash_including('order[inserted_at]' => 'asc')).and_return({
      'data' => [
        { 'id' => 'rev_100', 'property_id' => 'prop_1' },
        { 'id' => 'rev_200', 'property_id' => 'unknown_prop' }
      ],
      'meta' => { 'pagination' => { 'current_page' => 1, 'total_pages' => 1 } }
    })

    expect do
      described_class.perform_now
    end.to have_enqueued_job(ChannelManagers::IngestRevisionJob).with(hotel.id, 'rev_100')
  end
end
