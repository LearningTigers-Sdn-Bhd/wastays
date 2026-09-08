# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ColumnExportTable do
  Line = Struct.new(:day, :guest, :room, :amount)

  let(:columns) do
    HotelPortal::Reports::ReportColumns.build(
      columns: [
        HotelPortal::Reports::ReportColumns.column(key: "day", label: "Day", export_labels: [ "Day" ], pdf_label: "Day", pdf_width: 60, excel_width: 14, type: :date),
        HotelPortal::Reports::ReportColumns.column(key: "guest", label: "Guest", export_labels: [ "Guest", "Room" ], pdf_label: "Guest / Room", pdf_width: 90, excel_width: 20),
        HotelPortal::Reports::ReportColumns.column(key: "amount", label: "Amount", export_labels: [ "Amount" ], pdf_label: "Amount", pdf_width: 50, excel_width: 14, type: :money),
        HotelPortal::Reports::ReportColumns.column(key: "currency", label: "Currency", export_labels: [ "Currency" ], pdf_label: "Currency", pdf_width: 40, excel_width: 12)
      ],
      defaults: %w[day guest amount]
    )
  end
  let(:values) do
    lambda do |line, key, pdf|
      case key
      when "day" then pdf ? line.day.strftime("%d %b %Y") : line.day
      when "guest" then pdf ? "#{line.guest}\n#{line.room}" : [ line.guest, line.room ]
      when "amount" then line.amount
      when "currency" then "MYR"
      end
    end
  end
  let(:lines) { [ Line.new(Date.new(2026, 5, 6), "Aina", "101", 100.to_d) ] }

  def table(visible_columns)
    described_class.new(records: lines, columns:, visible_columns:, values:)
  end

  it "expands a two-label column for data exports and keeps one PDF column" do
    built = table(%w[guest amount])

    expect(built.headers).to eq([ "Guest", "Room", "Amount" ])
    expect(built.pdf_headers).to eq([ "Guest / Room", "Amount" ])
    expect(built.rows).to eq([ [ "Aina", "101", 100.to_d ] ])
    expect(built.pdf_rows).to eq([ [ "Aina\n101", 100.to_d ] ])
  end

  it "keeps a nil cell in place instead of dropping the column" do
    built = table(%w[day currency])
    allow(values).to receive(:call).and_return(nil)

    expect(described_class.new(records: lines, columns:, visible_columns: %w[day currency], values: ->(*) { nil }).rows)
      .to eq([ [ nil, nil ] ])
    expect(built.headers.size).to eq(2)
  end

  it "points at the money columns of each export format" do
    built = table(%w[guest amount])

    expect(built.money_indexes).to eq([ 2 ])
    expect(built.pdf_money_indexes).to eq([ 1 ])
  end

  it "gives the declared widths, and shares the PDF width when asked" do
    built = table(%w[guest amount])

    expect(built.excel_widths).to eq([ 20, 20, 14 ])
    expect(built.pdf_widths).to eq([ 90, 50 ])
    expect(built.pdf_widths(140).map(&:round)).to eq([ 90, 50 ])
  end

  it "writes the totals under their own columns and names the currency first" do
    built = table(%w[day guest amount currency])
    totals = { currency: "MYR", amount: 100.to_d }

    expect(built.total_row(totals)).to eq([ "TOTAL MYR", nil, nil, 100.to_d, "MYR" ])
    expect(built.total_row(totals, pdf: true)).to eq([ "TOTAL MYR", nil, 100.to_d, "MYR" ])
  end

  it "refuses a table without a visible column" do
    expect { table([]) }.to raise_error(ArgumentError, /at least one visible column/)
  end
end
