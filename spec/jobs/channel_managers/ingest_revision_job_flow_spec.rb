require 'rails_helper'

RSpec.describe ChannelManagers::IngestRevisionJob, type: :job do
  let(:hotel) { create(:hotel, preferred_channel_manager: 'channex') }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { create(:rate_plan, room_type: room_type) }
  let(:client_double) { instance_double(Channex::Client) }

  before do
    create(:channel_mapping, mappable: hotel, provider: 'channex', external_id: 'prop_1')
    create(:channel_mapping, mappable: room_type, provider: 'channex', external_id: 'rt_1')
    create(:channel_mapping, mappable: rate_plan, provider: 'channex', external_id: 'rp_1')
    create(:room_inventory, room_type: room_type, date: Date.new(2026, 6, 1), quantity: 2, status: 'open')

    allow(Channex::Client).to receive(:new).and_return(client_double)

    guest = create(:guest, name: 'Jane Guest', email: 'jane@example.com', phone: '+60120000000', country: 'Malaysia')
    allow_any_instance_of(GuestArrival::CreateOrMatchGuest).to receive(:call).and_return(OpenStruct.new(success?: true, guest: guest))
    allow(WebhookBroadcastJob).to receive(:perform_later)
  end

  it 'pulls revision, ingests booking, and acknowledges revision' do
    allow(client_double).to receive(:get).with('/booking_revisions/rev_100').and_return(
      {
        'data' => {
          'id' => 'ch_booking_1',
          'status' => 'new',
          'revision_id' => 1,
          'ota_reservation_id' => 'OTA-555',
          'arrival_date' => '2026-06-01',
          'departure_date' => '2026-06-02',
          'amount' => '200.0',
          'currency' => 'MYR',
          'ota_name' => 'booking.com',
          'customer' => {
            'name' => 'Jane Guest',
            'email' => 'jane@example.com',
            'phone' => '+60120000000',
            'country' => 'Malaysia'
          },
          'rooms' => [
            {
              'room_type_id' => 'rt_1',
              'rate_plan_id' => 'rp_1',
              'count' => 1,
              'amount' => '200.0'
            }
          ]
        }
      }
    )
    expect(client_double).to receive(:post).with('/booking_revisions/rev_100/ack').and_return({ 'meta' => { 'message' => 'Success' } })

    described_class.perform_now(hotel.id, 'rev_100')

    booking = Booking.find_by(channel_manager_reference: 'ch_booking_1')
    expect(booking).to be_present
    expect(booking.external_reference).to eq('OTA-555')
  end
end
