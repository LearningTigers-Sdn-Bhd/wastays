require "rails_helper"

RSpec.describe ChannelManagers::DiagnoseMappingService do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { create(:rate_plan, hotel: hotel) }
  let(:client_double) { instance_double(Channex::Client) }

  subject { described_class.new(hotel: hotel).call }

  before do
    allow(Channex::Client).to receive(:new).and_return(client_double)
  end

  context "when the hotel has no channel mapping" do
    it "returns an empty result without calling Channex" do
      expect(client_double).not_to receive(:get)

      result = subject

      expect(result.mismatched?).to be false
      expect(result.mismatches).to eq([])
      expect(result.correct_property_id).to be_nil
    end
  end

  context "when the mapped rate plan belongs to the currently mapped property" do
    it "reports no drift" do
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

      result = subject

      expect(result.mismatched?).to be false
      expect(result.mismatches).to eq([])
    end
  end

  context "when the mapped rate plan belongs to a different property" do
    it "reports the drift and the correct property/room type ids" do
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

      result = subject

      expect(result.mismatched?).to be true
      expect(result.correct_property_id).to eq("prop_real")
      expect(result.correct_room_type_ids).to eq(room_type.id => "rt_real")
      expect(result.mismatches).to contain_exactly(
        hash_including(
          room_type_id: room_type.id,
          rate_plan_id: rate_plan.id,
          expected_property_id: "prop_real"
        )
      )
    end
  end

  context "when the rate plan mapping is still pending" do
    it "skips it" do
      create(:channel_mapping, mappable: hotel, external_id: "prop_current")
      room_type_rate_plan = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      create(:channel_mapping, mappable: room_type_rate_plan, external_id: "pending")

      expect(client_double).not_to receive(:get)

      result = subject

      expect(result.mismatched?).to be false
    end
  end
end
