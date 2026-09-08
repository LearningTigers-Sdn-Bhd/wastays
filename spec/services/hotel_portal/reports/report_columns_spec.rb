# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ReportColumns do
  let(:columns) do
    [
      described_class.column(key: "date", label: "Date", export_labels: [ "Date" ], pdf_label: "Date", pdf_width: 60, excel_width: 14, type: :date),
      described_class.column(key: "guest", label: "Guest", export_labels: [ "Guest", "Room" ], pdf_label: "Guest", pdf_width: 90, excel_width: 20),
      described_class.column(key: "amount", label: "Amount", export_labels: [ "Amount" ], pdf_label: "Amount", pdf_width: 60, excel_width: 14, type: :money)
    ]
  end
  let(:built) { described_class.build(columns:, defaults: %w[date amount]) }

  it "gives text as the column type when the caller does not name one" do
    expect(built::BY_KEY.fetch("guest").type).to eq(:text)
  end

  it "publishes the keys, the defaults, and the lookup" do
    expect(built::KEYS).to eq(%w[date guest amount])
    expect(built::DEFAULT_KEYS).to eq(%w[date amount])
    expect(built::BY_KEY.keys).to eq(%w[date guest amount])
  end

  it "keeps the declared order and drops unknown keys" do
    expect(built.normalize(%w[amount bogus date])).to eq(%w[date amount])
    expect(built.selected(%w[amount date]).map(&:key)).to eq(%w[date amount])
  end

  it "refuses a default column that does not exist" do
    expect { described_class.build(columns:, defaults: %w[date bogus]) }
      .to raise_error(ArgumentError, /bogus/)
  end
end
