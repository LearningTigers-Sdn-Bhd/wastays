# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#format_number" do
    it "adds thousands delimiters" do
      expect(helper.format_number(10000)).to eq("10,000")
      expect(helper.format_number(1000000)).to eq("1,000,000")
    end

    it "supports precision with delimiter" do
      expect(helper.format_number(10000.5, precision: 2)).to eq("10,000.50")
    end

    it "handles blank and nil values" do
      expect(helper.format_number(nil)).to eq("")
      expect(helper.format_number("")).to eq("")
    end
  end

  describe "#format_currency" do
    it "delegates formatting to CurrencyFormatter with thousand separators" do
      expect(helper.format_currency(10000.5, currency: "MYR")).to eq("RM 10,000.50")
      expect(helper.format_currency(10000.5, currency: "MYR", symbol: false)).to eq("10,000.50")
    end
  end

  describe "#format_amount" do
    it "drops the cents when there are none" do
      expect(helper.format_amount(1_000_000)).to eq("1,000,000")
      expect(helper.format_amount(0)).to eq("0")
      expect(helper.format_amount(4_838.00)).to eq("4,838")
    end

    it "keeps the cents when they carry value" do
      expect(helper.format_amount(4_838.5)).to eq("4,838.50")
      expect(helper.format_amount(0.05)).to eq("0.05")
    end

    it "returns an empty string for a blank amount" do
      expect(helper.format_amount(nil)).to eq("")
    end
  end

  describe "#toast_flash_messages" do
    it "maps notice and alert flashes to RailsBlocks toast variants" do
      messages = helper.toast_flash_messages(ActionDispatch::Flash::FlashHash.new.tap { |flash| flash[:notice] = "Saved"; flash[:alert] = "Failed" })

      expect(messages).to include({ message: "Saved", options: { type: "success" } })
      expect(messages).to include({ message: "Failed", options: { type: "error" } })
    end

    it "supports structured flash[:toast] data" do
      messages = helper.toast_flash_messages(ActionDispatch::Flash::FlashHash.new.tap do |flash|
        flash[:toast] = { message: "Booking saved", description: "Guest checked in", type: "success" }
      end)

      expect(messages).to eq([ { message: "Booking saved", options: { type: "success", description: "Guest checked in" } } ])
    end

    it "preserves a same-origin action and rejects an external action URL" do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, base_url: "http://test.host"))
      safe_flash = ActionDispatch::Flash::FlashHash.new.tap do |flash|
        flash[:toast] = { message: "Done", action: { label: "View details", url: "/hotel/1/reports/night-audits/2" } }
      end
      unsafe_flash = ActionDispatch::Flash::FlashHash.new.tap do |flash|
        flash[:toast] = { message: "Done", action: { label: "View details", url: "https://evil.example/steal" } }
      end

      expect(helper.toast_flash_messages(safe_flash).sole.dig(:options, :action)).to eq(label: "View details", url: "/hotel/1/reports/night-audits/2")
      expect(helper.toast_flash_messages(unsafe_flash).sole.dig(:options, :action)).to be_nil
    end
  end

  describe "#pax_pricing_breakdown_items" do
    let(:account) { create(:account) }
    let(:hotel) { create(:hotel, account: account, allow_pax_pricing: true, pax_pricing_only: true, default_currency: "MYR") }
    let(:room_type) { create(:room_type, hotel: hotel, max_adults: 4, max_children: 2, base_price: 500.0) }

    def build_item(rate_plan:, adults:, children:, child_ages: [])
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 5, status: "open")
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 100.0)

      result = BookingEngine::CreateQuote.new(
        hotel_id: hotel.id,
        allocations: { "0" => { room_type_id: room_type.id, quantity: 1 } },
        check_in: Date.current, check_out: Date.current + 1,
        adults: adults, children: children, child_ages: child_ages,
        rate_plan_id: rate_plan.id,
        guest_name: "Test Guest", guest_email: "guest@example.com", guest_phone: "0123456789"
      ).call

      expect(result.success?).to eq(true)
      result.quote.booking_quote_items.first
    end

    it "uses the frozen age-band snapshot for children on an age-banded plan, not the flat multiplier" do
      rate_plan = create(:rate_plan, :age_banded, hotel: hotel, name: "Family Per-Pax", room_type: room_type, base_occupancy: 2, child_price_multiplier: 0.5)
      item = build_item(rate_plan: rate_plan, adults: 2, children: 2, child_ages: [ 8, 15 ])

      lines = helper.pax_pricing_breakdown_items(item, hotel, "MYR")
      child_line = lines.find { |l| l[:label].include?("Child") }

      # band(4-11) = 40, band(12-17) = 20 -> total children cost = 60, not 2 * 100 * 0.5 = 100
      expect(child_line[:detail]).to include("age-banded pricing")
      expect(child_line[:amount]).to include("60")
    end

    it "falls back to the flat child_price_multiplier when there are no age bands" do
      rate_plan = create(:rate_plan, hotel: hotel, name: "Per-Pax", sell_mode: "per_person", room_type: room_type, base_occupancy: 2, child_price_multiplier: 0.5)
      item = build_item(rate_plan: rate_plan, adults: 2, children: 1)

      lines = helper.pax_pricing_breakdown_items(item, hotel, "MYR")
      child_line = lines.find { |l| l[:label].include?("Child") }

      # 1 child * 100 * 0.5 = 50
      expect(child_line[:detail]).to include("50%")
      expect(child_line[:amount]).to include("50")
    end
  end
end
