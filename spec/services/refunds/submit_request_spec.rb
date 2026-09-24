require "rails_helper"

RSpec.describe Refunds::SubmitRequest do
  let(:hotel) { create(:hotel, status: "live") }
  let!(:policy) { create(:refund_policy, refund_percentage: 80, min_days_before_checkin: 3) }

  let(:bank_details) do
    {
      reason: "Charged twice for the minibar.",
      bank_name: "Maybank",
      account_holder_name: "Ahmad Zulkifli",
      account_number: "1234567890",
      account_type: "savings"
    }
  end

  def submit(booking, mode:, **extra)
    described_class.new(booking: booking, params: bank_details.merge(extra), mode: mode).call
  end

  it "refuses a mode it does not know" do
    booking = create(:booking, hotel: hotel, status: "confirmed")

    expect { described_class.new(booking: booking, params: bank_details, mode: :mid_stay) }
      .to raise_error(ArgumentError, /mid_stay/)
  end

  describe "the pre-stay mode" do
    let(:booking) do
      create(:booking, hotel: hotel, status: "confirmed", total_amount: 200.0,
        check_in: 10.days.from_now.to_date)
    end
    let(:params) do
      {
        reason: "Can't travel",
        bank_name: "Maybank",
        account_holder_name: "Jane Doe",
        account_number: "12345678",
        account_type: "savings"
      }
    end

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

    it "stays the default mode" do
      described_class.new(booking: booking, params: params).call

      expect(booking.reload.status).to eq("cancelled")
    end
  end

  describe "the post-stay mode" do
    let(:booking) do
      create(:booking, hotel: hotel, status: "completed", total_amount: 500.0,
        currency: "MYR", checked_out_at: 1.day.ago)
    end

    it "creates a pending request and leaves the status alone" do
      result = submit(booking, mode: :post_stay, refund_amount: "120.50")

      expect(result.success?).to be true
      expect(booking.reload.status).to eq("completed")
      expect(booking.refund_request.status).to eq("pending")
      expect(booking.refund_request.refund_amount).to eq(120.50)
    end

    it "works for a booking that is still in house" do
      in_house = create(:booking, hotel: hotel, status: "checked_in", total_amount: 500.0)

      result = submit(in_house, mode: :post_stay, refund_amount: "50")

      expect(result.success?).to be true
      expect(in_house.reload.status).to eq("checked_in")
    end

    it "asks for an amount when none is given" do
      result = submit(booking, mode: :post_stay, refund_amount: "")

      expect(result.success?).to be false
      expect(result.error).to include("enter the amount")
    end

    it "refuses an amount of zero" do
      result = submit(booking, mode: :post_stay, refund_amount: "0")

      expect(result.success?).to be false
      expect(result.error).to include("above zero")
    end

    it "refuses text in place of an amount" do
      result = submit(booking, mode: :post_stay, refund_amount: "a lot")

      expect(result.success?).to be false
      expect(result.error).to include("enter the amount")
    end

    it "refuses more than the guest paid" do
      result = submit(booking, mode: :post_stay, refund_amount: "500.01")

      expect(result.success?).to be false
      expect(result.error).to include("MYR 500.00")
    end

    it "refuses a second request while one is open" do
      submit(booking, mode: :post_stay, refund_amount: "100")

      result = submit(booking.reload, mode: :post_stay, refund_amount: "100")

      expect(result.success?).to be false
      expect(result.error).to eq(described_class::NOT_ELIGIBLE)
    end

    it "permits a resubmission after staff rejects one" do
      submit(booking, mode: :post_stay, refund_amount: "100")
      booking.refund_request.update!(status: "rejected", hotel_note: "Please send a receipt.")

      result = submit(booking.reload, mode: :post_stay, refund_amount: "80")

      expect(result.success?).to be true
      request = booking.reload.refund_request
      expect(request.status).to eq("pending")
      expect(request.refund_amount).to eq(80.0)
      expect(request.hotel_note).to be_nil
    end

    it "asks for the bank details when they are missing" do
      result = described_class.new(
        booking: booking,
        params: { reason: "Wrong charge", refund_amount: "100" },
        mode: :post_stay
      ).call

      expect(result.success?).to be false
      expect(result.error).to include("bank details")
    end
  end
end
