# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelDemoManagement::SeedRealtimeScenario do
  let(:logger) { HotelDemoManagement::ResetState::NoopLogger.new }
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, default_currency: "MYR") }
  let!(:user) { create(:user, account: account) }
  let!(:room_type) do
    create(:room_type, hotel: hotel, name: "Deluxe", quantity: 8, base_price: 200, room_numbers: %w[101 102 103 104 105 106 107 108])
  end
  let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Standard Rate", currency: "MYR") }

  let(:reset_success) do
    HotelDemoManagement::ResetState::Result.new(success?: true, hotel: hotel)
  end

  before do
    allow(HotelDemoManagement::ResetState).to receive(:new).and_return(instance_double(HotelDemoManagement::ResetState, call: reset_success))
    allow(Bookings::TransitionStatus).to receive(:new).and_return(instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: true)))
    allow(Folios::PostCategoryCharge).to receive(:call).and_return(OpenStruct.new(success?: true))
    allow(HotelOps::RunNightAudit).to receive(:new).and_return(instance_double(HotelOps::RunNightAudit, call: OpenStruct.new(success?: true)))
  end

  describe "#call" do
    it "calls reset state before seeding realtime bookings" do
      service = instance_double(HotelDemoManagement::ResetState, call: reset_success)
      allow(HotelDemoManagement::ResetState).to receive(:new).and_return(service)

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).to be_success
      expect(HotelDemoManagement::ResetState).to have_received(:new).with(hotel: hotel, logger: logger, embed: false)
      expect(service).to have_received(:call)
      expect(hotel.bookings.count).to eq(25)
    end

    it "creates demo guests, bookings, booking rooms, and payment transactions" do
      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).to be_success
      expect(Guest.where(email: "ahmad.ibrahim@example.com")).to exist
      expect(hotel.bookings.count).to eq(25)
      expect(BookingRoom.joins(:booking).where(bookings: { hotel_id: hotel.id }).count).to eq(25)
      expect(PaymentTransaction.joins(:booking).where(bookings: { hotel_id: hotel.id }, gateway: "manual", status: "captured").count).to eq(25)
    end

    it "runs booking lifecycle services and night audits" do
      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).to be_success
      expect(Bookings::TransitionStatus).to have_received(:new).at_least(:once)
      expect(Folios::PostCategoryCharge).to have_received(:call).at_least(:once)
      expect(HotelOps::RunNightAudit).to have_received(:new).exactly(5).times
    end

    it "returns failure when reset state fails" do
      reset_failure = HotelDemoManagement::ResetState::Result.new(success?: false, hotel: hotel, error: "reset failed")
      allow(HotelDemoManagement::ResetState).to receive(:new).and_return(instance_double(HotelDemoManagement::ResetState, call: reset_failure))

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).not_to be_success
      expect(result.error).to eq("reset failed")
      expect(hotel.bookings).to be_empty
    end

    it "returns failure when a lifecycle service fails" do
      failed_transition = instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: false, error: "posting blocked"))
      allow(Bookings::TransitionStatus).to receive(:new).and_return(failed_transition)

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).not_to be_success
      expect(result.error).to include("posting blocked")
    end

    it "returns failure when room setup is invalid after reset" do
      rate_plan.destroy!

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).not_to be_success
      expect(result.error).to include("at least one rate plan")
    end
  end
end
