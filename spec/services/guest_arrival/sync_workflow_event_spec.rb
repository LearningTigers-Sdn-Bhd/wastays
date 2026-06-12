require "rails_helper"

RSpec.describe GuestArrival::SyncWorkflowEvent do
  let(:booking) { create(:booking, pre_checkin_status: "pending") }
  let!(:pre_checkin) { create(:pre_checkin, booking: booking, status: "pending", metadata: {}) }

  it "updates status for flow_started" do
    result = described_class.new(booking, { event_type: "flow_started", data: {} }).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.status).to eq("in_progress")
    expect(booking.reload.pre_checkin_status).to eq("in_progress")
    expect(BookingAuditLog.where(auditable: booking).last).to have_attributes(
      action_type: "pre_checkin_updated",
      source: "system",
      category: "stay"
    )
  end

  it "finalizes pre-checkin on flow_completed" do
    result = described_class.new(booking, { event_type: "flow_completed", data: { foo: "bar" } }).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.status).to eq("completed")
    expect(pre_checkin.metadata["final_payload"]).to eq({ "foo" => "bar" })
    expect(booking.reload.guarantee_method).to eq("pre_checkin_completed")
    expect(BookingAuditLog.where(auditable: booking).last).to have_attributes(
      action_type: "pre_checkin_completed",
      source: "system"
    )
  end

  it "updates document status on document_uploaded event" do
    result = described_class.new(booking, { event_type: "document_uploaded", data: {} }).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.document_status).to eq("uploaded")
  end

  it "updates signature status on signature_completed event" do
    result = described_class.new(booking, { event_type: "signature_completed", data: {} }).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.signature_status).to eq("signed")
  end

  it "marks booking and pre-checkin failed on flow_failed" do
    result = described_class.new(booking, { event_type: "flow_failed", data: {} }).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.status).to eq("failed")
    expect(booking.reload.pre_checkin_status).to eq("failed")
  end

  it "returns failure when booking has no pre-checkin record" do
    orphan_booking = create(:booking, pre_checkin_status: nil)

    result = described_class.new(orphan_booking, { event_type: "flow_started", data: {} }).call

    expect(result.success?).to be(false)
    expect(result.message).to include("not found")
  end
end
