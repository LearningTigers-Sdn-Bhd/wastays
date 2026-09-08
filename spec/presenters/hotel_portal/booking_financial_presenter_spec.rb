# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingFinancialPresenter do
  let(:booking) do
    instance_double(
      Booking,
      confirmation_token: "WS-123",
      formatted_reservation_number: "HTL-26100006",
      guest_name: "John Doe",
      status: "confirmed",
      currency: "MYR",
      total_amount: 100.5,
      tax_total: 10.0,
      margin_amount: 5.0,
      net_amount: 85.5,
      created_at: Time.zone.local(2026, 6, 9, 12, 0)
    )
  end

  describe "#booking_number" do
    it "returns the formatted reservation number" do
      expect(presenter.booking_number).to eq("HTL-26100006")
    end
  end
  let(:presenter) { described_class.new(booking) }

  describe "#confirmation_token" do
    it "returns the booking token" do
      expect(presenter.confirmation_token).to eq("WS-123")
    end
  end

  describe "status presentation" do
    it "provides the shared badge label and variant" do
      expect(presenter.status_label).to eq("Confirmed")
      expect(presenter.status_badge_variant).to eq(:info)
    end
  end

  describe "#total_amount" do
    it "formats the total amount" do
      expect(presenter.total_amount).to eq("MYR 100.50")
    end
  end

  describe "#tax_total" do
    it "formats the tax total" do
      expect(presenter.tax_total).to eq("MYR 10.00")
    end
  end

  describe "#formatted_created_at" do
    it "formats the creation date" do
      expect(presenter.formatted_created_at).to eq("09 Jun 2026")
    end
  end
end
