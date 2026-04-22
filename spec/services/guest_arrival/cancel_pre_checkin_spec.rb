require "rails_helper"

RSpec.describe GuestArrival::CancelPreCheckin do
  let(:booking) { create(:booking, pre_checkin_status: "completed") }

  it "rejects cancellation when pre-checkin is completed" do
    pre_checkin = create(:pre_checkin, booking: booking, status: "completed")

    result = described_class.new(booking: booking, pre_checkin: pre_checkin).call

    expect(result.success?).to be(false)
    expect(result.message).to include("cannot be cancelled")
  end

  it "resets statuses when pre-checkin is not completed" do
    pre_checkin = create(:pre_checkin, booking: booking, status: "in_progress", document_status: "uploaded", signature_status: "signed", completed_at: Time.current)

    result = described_class.new(booking: booking, pre_checkin: pre_checkin).call

    expect(result.success?).to be(true)
    expect(pre_checkin.reload.status).to eq("pending")
    expect(pre_checkin.document_status).to eq("pending")
    expect(pre_checkin.signature_status).to eq("pending")
    expect(pre_checkin.completed_at).to be_nil
    expect(booking.reload.pre_checkin_status).to eq("pending")
  end
end
