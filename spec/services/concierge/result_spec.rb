require "rails_helper"

RSpec.describe Concierge::Result do
  describe ".success" do
    it "creates a successful result with success? set to true" do
      result = described_class.success(booking: "test_booking")
      expect(result.success?).to be true
      expect(result.booking).to eq("test_booking")
    end

    it "accepts multiple attributes" do
      result = described_class.success(
        booking: "booking1",
        room_number: "101",
        message: "Check-in successful"
      )
      expect(result.success?).to be true
      expect(result.booking).to eq("booking1")
      expect(result.room_number).to eq("101")
      expect(result.message).to eq("Check-in successful")
    end
  end

  describe ".failure" do
    it "creates a failed result with success? set to false" do
      result = described_class.failure(error_code: "INVALID_BOOKING")
      expect(result.success?).to be false
      expect(result.error_code).to eq("INVALID_BOOKING")
    end

    it "accepts multiple attributes" do
      result = described_class.failure(
        error_code: "NOT_FOUND",
        message: "Booking not found"
      )
      expect(result.success?).to be false
      expect(result.error_code).to eq("NOT_FOUND")
      expect(result.message).to eq("Booking not found")
    end
  end

  describe "attributes" do
    it "has all expected attributes" do
      result = described_class.new(
        success?: true,
        booking: "booking1",
        request: "request1",
        check_out_request: "checkout1",
        room_number: "101",
        error_code: nil,
        message: "Success"
      )
      expect(result.success?).to be true
      expect(result.booking).to eq("booking1")
      expect(result.request).to eq("request1")
      expect(result.check_out_request).to eq("checkout1")
      expect(result.room_number).to eq("101")
      expect(result.error_code).to be_nil
      expect(result.message).to eq("Success")
    end
  end
end
