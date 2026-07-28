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
  end
end
