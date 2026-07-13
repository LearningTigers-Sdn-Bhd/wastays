# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
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
