# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingFinancialPresenter do
  let(:booking) do
    instance_double(
      Booking,
      confirmation_token: "WS-123",
      guest_name: "John Doe",
      status: "confirmed",
      total_amount: 100.5,
      tax_total: 10.0,
      margin_amount: 5.0,
      net_amount: 85.5,
      created_at: Time.zone.local(2026, 6, 9, 12, 0)
    )
  end
  let(:presenter) { described_class.new(booking) }

  describe "#confirmation_token" do
    it "returns the booking token" do
      expect(presenter.confirmation_token).to eq("WS-123")
    end
  end

  describe "#total_amount" do
    it "formats the total amount" do
      expect(presenter.total_amount).to eq("100.50")
    end
  end

  describe "#tax_total" do
    it "formats the tax total" do
      expect(presenter.tax_total).to eq("10.00")
    end
  end

  describe "#formatted_created_at" do
    it "formats the creation date" do
      expect(presenter.formatted_created_at).to eq("09 Jun 2026")
    end
  end
end
