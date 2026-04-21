require "rails_helper"

RSpec.describe Complaints::SyncRequest do
  let(:booking) { create(:booking) }

  it "creates complaint request from payload" do
    payload = { data: { complaint: "AC leaking", external_id: "cmp-1", status: "pending", date: "2026-04-20" } }
    result = described_class.new(booking, payload).call

    expect(result.success?).to be(true)
    expect(result.complaint_request).to be_persisted
    expect(result.complaint_request.external_id).to eq("cmp-1")
  end

  it "fails when complaint details missing" do
    result = described_class.new(booking, { data: {} }).call
    expect(result.success?).to be(false)
  end
end
