# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::Columns do
  describe ".normalize" do
    it "keeps known columns in the canonical order" do
      columns = described_class.normalize([ :remarks, "unknown", :room_number, :remarks ])

      expect(columns).to eq(%w[room_number remarks])
    end

    it "returns no columns for an empty value" do
      expect(described_class.normalize(nil)).to eq([])
    end
  end

  describe ".selected" do
    it "returns the column definitions for the normalized keys" do
      columns = described_class.selected(%w[nights room_type])

      expect(columns.map(&:key)).to eq(%w[room_type nights])
      expect(columns.map(&:type)).to eq(%i[text integer])
    end
  end
end
