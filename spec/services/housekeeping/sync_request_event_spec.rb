require "rails_helper"

RSpec.describe Housekeeping::SyncRequestEvent do
  let(:booking) { create(:booking, status: "checked_in") }

  it "creates housekeeping request from payload" do
    payload = { data: { requests: [ "Towel", "Water" ], external_id: "hk-1", status: "pending", date: "2026-04-20" } }
    result = described_class.new(booking, payload).call

    expect(result.success?).to be(true)
    expect(result.housekeeping_request).to be_persisted
    expect(result.housekeeping_request.external_id).to eq("hk-1")
    expect(result.housekeeping_request.request_details).to eq("Towel, Water")
    expect(result.housekeeping_request.work_context).to eq("guest_request")
  end

  it "uses pending status for unknown status" do
    payload = { data: { requests: "Clean room", status: "bogus" } }
    result = described_class.new(booking, payload).call

    expect(result.success?).to be(true)
    expect(result.housekeeping_request.status).to eq("pending")
  end

  it "accepts a pre-arrival booking" do
    pre_arrival = create(:booking, status: "confirmed")

    result = described_class.new(pre_arrival, { data: { requests: "Clean room" } }).call

    expect(result.success?).to be(true)
    expect(result.housekeeping_request.work_context).to eq("guest_request")
  end

  it "rejects a booking whose stay is over" do
    departed = create(:booking, status: "completed")

    result = described_class.new(departed, { data: { requests: "Clean room" } }).call

    expect(result.success?).to be(false)
  end
end
