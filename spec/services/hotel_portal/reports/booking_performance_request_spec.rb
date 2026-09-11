# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::BookingPerformanceRequest do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  def build(params)
    described_class.new(
      hotel:, user:, params: ActionController::Parameters.new(params).permit!,
      start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 31), date_preset: "custom"
    )
  end

  it "gives the default columns when the user saved no preference" do
    expect(build({}).visible_columns).to eq(HotelPortal::Reports::BookingPerformanceColumns::DEFAULT_KEYS)
  end

  it "reads the saved columns of the user" do
    ReportViewPreference.create!(hotel:, user:, report_key: "booking_performance", visible_columns: %w[guest net])

    expect(build({}).visible_columns).to eq(%w[guest net])
  end

  it "falls back to the booking date when the grouping column is hidden" do
    ReportViewPreference.create!(hotel:, user:, report_key: "booking_performance", visible_columns: %w[guest net])

    expect(build({ group_by: "source" }).group_by).to eq("booking_date")
    expect(build({ group_by: "booking_date" }).group_by).to eq("booking_date")
  end

  it "keeps a grouping whose column stays on screen" do
    expect(build({ group_by: "source" }).group_by).to eq("source")
  end

  it "leaves a filter unset when the request does not name it" do
    expect(build({}).filters.values).to all(be_nil)
  end

  it "reads the old single collector parameter" do
    expect(build({ fund_collector: "wastays" }).filters[:fund_collectors]).to eq(%w[wastays])
    expect(build({ fund_collectors: %w[hotel], fund_collector: "wastays" }).filters[:fund_collectors]).to eq(%w[hotel])
  end

  it "reads an empty filter as a filter that matches nothing" do
    expect(build({ statuses: %w[__none__] }).filters[:statuses]).to eq([])
    expect(build({ statuses: %w[__all__] }).filters[:statuses]).to eq([])
  end

  it "exports the whole report when the user selected no row" do
    request = build({})

    expect(request.export_report).to equal(request.report)
  end

  it "exports only the selected rows" do
    kept = create(:booking, hotel:, created_at: Time.zone.local(2026, 5, 6, 12, 0))
    create(:booking, hotel:, created_at: Time.zone.local(2026, 5, 6, 13, 0))

    request = build({ selected_booking_ids: [ kept.id ] })

    expect(request.export_report.rows.map(&:booking_id)).to eq([ kept.id ])
  end
end
