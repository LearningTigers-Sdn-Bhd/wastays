require "rails_helper"

RSpec.describe ChannelManagers::RepairMappingService do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { create(:rate_plan, hotel: hotel) }
  let(:client_double) { instance_double(Channex::Client) }

  subject { described_class.new(hotel: hotel).call }

  before do
    allow(Channex::Client).to receive(:new).and_return(client_double)
  end

  context "when there is no mapping drift" do
    it "returns success without changing any mapping" do
      create(:channel_mapping, mappable: hotel, external_id: "prop_current")
      room_type_rate_plan = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      create(:channel_mapping, mappable: room_type_rate_plan, external_id: "rp_1")

      allow(client_double).to receive(:get).with("/rate_plans/rp_1").and_return(
        {
          "data" => {
            "relationships" => {
              "property" => { "data" => { "id" => "prop_current" } },
              "room_type" => { "data" => { "id" => "rt_current" } }
            }
          }
        }
      )

      expect(ChannelManagers::SyncJob).not_to receive(:perform_later)

      result = subject

      expect(result.success?).to be true
      expect(result.message).to match(/No mapping drift detected/)
      expect(hotel.channel_mapping.reload.external_id).to eq("prop_current")
    end
  end

  context "when drift is detected" do
    it "repoints the hotel and room type mappings and triggers a full refresh" do
      create(:channel_mapping, mappable: hotel, external_id: "prop_stale")
      room_type_channel_mapping = create(:channel_mapping, mappable: room_type, external_id: "rt_stale")
      room_type_rate_plan = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      create(:channel_mapping, mappable: room_type_rate_plan, external_id: "rp_1")

      allow(client_double).to receive(:get).with("/rate_plans/rp_1").and_return(
        {
          "data" => {
            "relationships" => {
              "property" => { "data" => { "id" => "prop_real" } },
              "room_type" => { "data" => { "id" => "rt_real" } }
            }
          }
        }
      )

      expect(ChannelManagers::SyncJob).to receive(:perform_later).with(
        hotel.id, anything, anything, hash_including(sync_availability: true, sync_rates: true, sync_restrictions: true)
      )

      result = subject

      expect(result.success?).to be true
      expect(result.message).to match(/Repaired 1 mismatched mapping/)
      expect(hotel.channel_mapping.reload.external_id).to eq("prop_real")
      expect(room_type_channel_mapping.reload.external_id).to eq("rt_real")
    end

    it "creates a room type mapping when one didn't exist yet" do
      create(:channel_mapping, mappable: hotel, external_id: "prop_stale")
      room_type_rate_plan = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      create(:channel_mapping, mappable: room_type_rate_plan, external_id: "rp_1")

      allow(client_double).to receive(:get).with("/rate_plans/rp_1").and_return(
        {
          "data" => {
            "relationships" => {
              "property" => { "data" => { "id" => "prop_real" } },
              "room_type" => { "data" => { "id" => "rt_real" } }
            }
          }
        }
      )
      allow(ChannelManagers::SyncJob).to receive(:perform_later)

      expect { subject }.to change { room_type.reload.channel_mapping&.external_id }.from(nil).to("rt_real")
    end
  end

  context "when saving the repaired mapping fails" do
    it "returns a failure result" do
      create(:channel_mapping, mappable: hotel, external_id: "prop_stale")
      room_type_rate_plan = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      create(:channel_mapping, mappable: room_type_rate_plan, external_id: "rp_1")

      allow(client_double).to receive(:get).with("/rate_plans/rp_1").and_return(
        {
          "data" => {
            "relationships" => {
              "property" => { "data" => { "id" => "prop_real" } },
              "room_type" => { "data" => { "id" => "rt_real" } }
            }
          }
        }
      )
      allow_any_instance_of(ChannelMapping).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(hotel.channel_mapping))

      result = subject

      expect(result.success?).to be false
      expect(result.message).to be_present
    end
  end
end
