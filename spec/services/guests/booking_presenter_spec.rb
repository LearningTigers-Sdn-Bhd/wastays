# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::BookingPresenter do
  let(:booking) do
    build(:booking,
      check_in: Time.zone.parse("2026-07-01 14:00:00"),
      check_out: Time.zone.parse("2026-07-03 12:00:00"),
      status: "confirmed",
      currency: "MYR",
      total_amount: 300.0,
      tourism_tax_amount: 20.0,
      pre_checkin_status: "pending",
      created_at: Time.zone.parse("2026-06-30 08:30:00")
    )
  end
  let(:presenter) { described_class.new(booking) }

  describe "#check_in_formatted" do
    it "returns formatted check-in date" do
      expect(presenter.check_in_formatted).to eq("01 Jul 2026")
    end
  end

  describe "#check_out_formatted" do
    it "returns formatted check-out date" do
      expect(presenter.check_out_formatted).to eq("03 Jul 2026")
    end
  end

  describe "#nights_count" do
    it "returns duration in nights" do
      expect(presenter.nights_count).to eq(2)
    end
  end

  describe "#nights_label" do
    it "returns pluralized nights label" do
      expect(presenter.nights_label).to eq("2 nights")
    end
  end

  describe "#status_humanized" do
    it "returns humanized status" do
      expect(presenter.status_humanized).to eq("Confirmed")
    end
  end

  describe "#formatted_total_amount" do
    it "returns formatted currency and amount" do
      expect(presenter.formatted_total_amount).to eq("RM 300.00")
    end

    it "labels a currency the property does not trade in every day" do
      booking.currency = "SGD"

      expect(presenter.formatted_total_amount).to eq("S$ 300.00")
    end

    it "drops the decimals on a zero-decimal currency" do
      booking.currency = "JPY"

      expect(presenter.formatted_total_amount).to eq("¥ 300")
    end
  end

  describe "#formatted_tourism_tax_amount" do
    it "returns formatted tax amount" do
      expect(presenter.formatted_tourism_tax_amount).to eq("Tax RM 20.00")
    end
  end

  describe "#status_badge_variant" do
    it "maps each status onto a badge variant" do
      {
        "confirmed" => :success,
        "checked_in" => :success,
        "completed" => :success,
        "cancelled" => :destructive,
        "voided" => :destructive,
        "no_show" => :destructive,
        "pending" => :warning,
        "no_show_detected" => :warning
      }.each do |status, variant|
        booking.status = status
        expect(described_class.new(booking).status_badge_variant).to eq(variant)
      end
    end
  end

  describe "#created_at_time_formatted" do
    it "returns formatted created_at time" do
      expect(presenter.created_at_time_formatted).to eq("08:30 AM")
    end
  end

  describe "#created_at_date_formatted" do
    it "returns formatted created_at date" do
      expect(presenter.created_at_date_formatted).to eq("30 Jun 2026")
    end
  end

  describe "#pre_checkin_status_label" do
    it "returns humanized pre_checkin status" do
      expect(presenter.pre_checkin_status_label).to eq("Pending")
    end
  end
end
