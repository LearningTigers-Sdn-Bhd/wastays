require "rails_helper"

RSpec.describe Refunds::SubmitRequest do
  let(:booking) { create(:booking, status: "confirmed", total_amount: 200.0, check_in: 10.days.from_now.to_date) }
  let(:params) do
    {
      reason: "Can't travel",
      bank_name: "Maybank",
      account_holder_name: "Jane Doe",
      account_number: "12345678",
      account_type: "savings"
    }
  end

  before { create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80) }

  it "creates refund request and cancels booking when eligible" do
    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be(true)
    expect(booking.reload.status).to eq("cancelled")
    expect(booking.refund_request).to be_present
    expect(booking.refund_request.refund_amount.to_f).to eq(160.0)
  end

  it "fails when policy does not exist" do
    RefundPolicy.delete_all

    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be(false)
    expect(result.error).to include("currently unavailable")
  end

  it "resubmits rejected refund request" do
    create(:refund_request, booking: booking, status: "rejected", refund_amount: 100.0)
    booking.transition_status_to!("cancelled", event: "cancel")

    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be(true)
    expect(booking.refund_request.reload.status).to eq("pending")
    expect(booking.refund_request.refund_amount.to_f).to eq(160.0)
  end

  it "fails when check-in is too close to policy minimum days" do
    booking.update!(check_in: 1.day.from_now.to_date)

    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be(false)
    expect(result.error).to include("too close to check-in")
  end

  it "fails when booking already has a refund request" do
    create(:refund_request, booking: booking, status: "pending")

    result = described_class.new(booking: booking, params: params).call

    expect(result.success?).to be(false)
    expect(result.error).to include("already have a refund request")
  end

  it "returns bank details validation message for invalid submission" do
    invalid_params = params.merge(bank_name: "")

    result = described_class.new(booking: booking, params: invalid_params).call

    expect(result.success?).to be(false)
    expect(result.error).to include("complete your bank details")
  end
end
