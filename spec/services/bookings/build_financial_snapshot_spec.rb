# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::BuildFinancialSnapshot do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:check_in) { Date.current + 1.day }
  let(:check_out) { Date.current + 3.days }
  let(:guest_country) { "Malaysia" }

  before do
    # Create room rates for the stay period
    (check_in...check_out).each do |date|
      create(:room_rate, room_type: room_type, date: date, price: 100.0)
    end
  end

  describe "#call" do
    context "with room_type" do
      let(:service) do
        described_class.new(
          hotel: hotel,
          check_in: check_in,
          check_out: check_out,
          guest_country: guest_country,
          room_type: room_type
        )
      end

      before do
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        room_code.update!(is_taxable: true)
        room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      end

      it "calculates room total correctly" do
        result = service.call
        expect(result.room_total).to eq(200.0)
      end

      it "includes ROOM tax rule lines" do
        result = service.call
        expect(result.tax_lines).not_to be_empty
        # SST 8% of 200 = 16
        sst_line = result.tax_lines.find { |l| l["type"] == "sst" }
        expect(sst_line["amount"].to_d).to eq(16.0)
        expect(sst_line["transaction_code_system_key"]).to eq("sst_tax")
        expect(sst_line["transaction_code_code"]).to eq("TAX_SST")
      end
    end

    context "with manual_total_amount" do
      let(:service) do
        described_class.new(
          hotel: hotel,
          check_in: check_in,
          check_out: check_out,
          guest_country: guest_country,
          manual_total_amount: 500.0
        )
      end

      before do
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        room_code.update!(is_taxable: true)
        room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      end

      it "uses manual total amount" do
        result = service.call
        expect(result.room_total).to eq(500.0)
        expect(result.tax_total).to eq(40.0) # 8% of 500
      end
    end

    context "with foreign guest and tourism tax" do
      let(:guest_country) { "Singapore" }
      let(:hotel) { create(:hotel, sst_enabled: false, tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
      let(:service) do
        described_class.new(
          hotel: hotel,
          check_in: check_in,
          check_out: check_out,
          guest_country: guest_country,
          room_type: room_type
        )
      end

      before do
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        room_code.update!(is_taxable: true)
        room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
      end

      it "calculates tourism tax" do
        result = service.call
        tourism_line = result.tax_lines.find { |l| l["type"] == "tourism_tax" }
        # 10.0 per night * 2 nights = 20.0
        expect(tourism_line["amount"].to_d).to eq(20.0)
        expect(tourism_line["transaction_code_system_key"]).to eq("tourism_tax")
        expect(tourism_line["transaction_code_code"]).to eq("TAX_TTX")
      end
    end

    context "with custom hotel taxes" do
      let!(:hotel_tax) { create(:hotel_tax, hotel: hotel, name: "Dewan Bandaraya Kota Kinabalu", code: "DBKK", rate_type: "flat", amount: 12) }
      let(:service) do
        described_class.new(
          hotel: hotel,
          check_in: check_in,
          check_out: check_out,
          guest_country: guest_country,
          room_type: room_type
        )
      end

      before do
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        room_code.update!(is_taxable: true)
        room_code.transaction_code_taxes.create!(hotel_tax: hotel_tax)
      end

      it "includes the custom tax transaction code in the tax snapshot" do
        result = service.call
        tax_line = result.tax_lines.find { |line| line["name"] == hotel_tax.name }

        expect(tax_line["transaction_code_system_key"]).to eq("hotel_tax_#{hotel_tax.id}")
        expect(tax_line["transaction_code_code"]).to eq("TAX_DBKK")
      end
    end

    context "with ROOM transaction code tax rules" do
      let(:guest_country) { "Singapore" }
      let(:hotel) { create(:hotel, sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
      let!(:selected_service_charge) { create(:hotel_tax, hotel: hotel, name: "Service Charge", code: "SC", rate_type: "percentage", amount: 10) }
      let!(:unselected_service_tax) { create(:hotel_tax, hotel: hotel, name: "Service Tax", code: "ST", rate_type: "percentage", amount: 8) }
      let(:service) do
        described_class.new(
          hotel: hotel,
          check_in: check_in,
          check_out: check_out,
          guest_country: guest_country,
          room_type: room_type
        )
      end

      before do
        room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
        room_code.update!(is_taxable: true)
        room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
        room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
        room_code.transaction_code_taxes.create!(hotel_tax: selected_service_charge)
      end

      it "uses selected ROOM tax rules and excludes unselected hotel taxes" do
        result = service.call

        expect(result.tax_lines.map { |line| line["name"] }).to contain_exactly("SST 8%", "Tourism Tax", "Service Charge")
        expect(result.tax_lines.find { |line| line["name"] == "SST 8%" }["amount"].to_d).to eq(16.0)
        expect(result.tax_lines.find { |line| line["name"] == "Tourism Tax" }["amount"].to_d).to eq(20.0)
        expect(result.tax_lines.find { |line| line["name"] == "Service Charge" }["amount"].to_d).to eq(20.0)
        expect(result.tax_lines.map { |line| line["name"] }).not_to include(unselected_service_tax.name)
      end

      it "stores transaction code metadata for generated tax postings" do
        result = service.call
        first_day_tax_lines = result.tax_posting_snapshot.fetch(check_in.iso8601)

        expect(first_day_tax_lines.map { |line| line["source"] }.uniq).to eq([ "transaction_code_tax_rule" ])
        expect(first_day_tax_lines.find { |line| line["type"] == "sst" }["transaction_code_system_key"]).to eq("sst_tax")
        expect(first_day_tax_lines.find { |line| line["type"] == "tourism_tax" }["transaction_code_system_key"]).to eq("tourism_tax")
        expect(first_day_tax_lines.find { |line| line["name"] == "Service Charge" }["transaction_code_system_key"]).to eq("hotel_tax_#{selected_service_charge.id}")
      end

      it "does not apply tourism tax for Malaysian guests" do
        result = described_class.new(
          hotel: hotel,
          check_in: check_in,
          check_out: check_out,
          guest_country: "Malaysia",
          room_type: room_type
        ).call

        expect(result.tax_lines.map { |line| line["type"] }).not_to include("tourism_tax")
      end
    end
  end
end
