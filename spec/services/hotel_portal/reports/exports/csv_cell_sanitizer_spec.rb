# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::Exports::CsvCellSanitizer do
  it "neutralizes spreadsheet formula prefixes without changing safe text" do
    dangerous = [ "=SUM(A1:A2)", "+cmd", "-cmd", "@cmd", "\tcmd", "\rcmd" ]

    expect(dangerous.map { |value| described_class.call(value) }).to eq(dangerous.map { |value| "'#{value}" })
    expect(described_class.call("safe text")).to eq("safe text")
    expect(described_class.call(nil)).to be_nil
  end
end
