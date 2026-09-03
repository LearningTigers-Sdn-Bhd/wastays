# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportViewPreferences::Save do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }

  it "saves allowed columns in canonical order and rejects an empty selection" do
    result = described_class.new(
      hotel:, user:, report_key: "daily_report_cashier_activity",
      columns: HotelPortal::Reports::CashierActivityColumns,
      visible_columns: %w[amount removed date_time]
    ).call

    expect(result).to be_success
    expect(result.visible_columns).to eq(%w[date_time amount])

    empty = described_class.new(
      hotel:, user:, report_key: "another_report",
      columns: HotelPortal::Reports::CashierActivityColumns,
      visible_columns: %w[removed]
    ).call
    expect(empty).not_to be_success
    expect(empty.error).to eq("Keep at least one column visible.")
  end
end
