require "rails_helper"

RSpec.describe RatePlans::RemoveRoomType do
  let(:hotel) { create(:hotel) }
  let(:rate_plan) { create(:rate_plan, :custom, hotel: hotel) }
  let(:first_room) { create(:room_type, hotel: hotel) }
  let(:second_room) { create(:room_type, hotel: hotel) }

  before do
    create(:room_type_rate_plan, rate_plan: rate_plan, room_type: first_room)
    create(:room_type_rate_plan, rate_plan: rate_plan, room_type: second_room)
  end

  it "removes an unreferenced assignment" do
    result = described_class.call(rate_plan: rate_plan, room_type: first_room)

    expect(result).to be_success
    expect(rate_plan.reload.room_types).to contain_exactly(second_room)
  end

  it "keeps the final room category" do
    rate_plan.room_type_rate_plans.find_by(room_type: second_room).destroy!

    result = described_class.call(rate_plan: rate_plan, room_type: first_room)

    expect(result).not_to be_success
    expect(result.error).to include("at least one room category")
  end

  it "blocks a room category used by a matching booking" do
    booking = create(:booking, hotel: hotel)
    create(:booking_room, booking: booking, room_type: first_room, rate_plan: rate_plan)

    result = described_class.call(rate_plan: rate_plan, room_type: first_room)

    expect(result).not_to be_success
    expect(result.error).to include("existing bookings")
    expect(rate_plan.reload.room_types).to include(first_room)
  end

  it "never changes the room bound to a Standard Rate" do
    standard = first_room.standard_rate_plan

    result = described_class.call(rate_plan: standard, room_type: first_room)

    expect(result).not_to be_success
    expect(result.error).to include("Standard Rate")
  end

  it "enqueues deletion for an existing channel-side assignment mapping" do
    hotel.update!(preferred_channel_manager: "channex")
    assignment = rate_plan.room_type_rate_plans.find_by!(room_type: first_room)
    create(:channel_mapping, mappable: assignment, provider: "channex", external_id: "channel-rate-123")
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.call(rate_plan: rate_plan, room_type: first_room)

    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |item| item["job_class"] == "ChannelManagers::SyncStructureJob" }
    expect(job["arguments"]).to include("RoomTypeRatePlan", nil, "delete")
    expect(job["arguments"].last).to include("external_id" => "channel-rate-123")
  end
end
