# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe Reports::HousekeepingTasksPdfGenerator do
  let(:hotel) { create(:hotel) }

  describe "#call" do
    it "renders the selected date and preparer in the shared frame" do
      pdf = described_class.new(
        hotel: hotel,
        rooms: [],
        selected_date: Date.new(2026, 8, 17),
        prepared_by: "Housekeeping Manager",
        visible_columns: HousekeepingTasks::Columns::KEYS
      ).call
      text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

      expect(text).to include("Housekeeping Tasks", "SELECTED DATE", "17 Aug 2026", "PREPARED BY", "Housekeeping Manager")
    end
  end
end
