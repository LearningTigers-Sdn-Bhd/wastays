# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportViewPreferences::Read do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:columns) { HotelPortal::Reports::CashierActivityColumns }
  let(:reader) { described_class.new(hotel:, user:, report_key: "daily_report_cashier_activity", columns:) }

  it "uses defaults, normalizes stored keys, and resets the preference" do
    expect(reader.visible_columns).to eq(columns::DEFAULT_KEYS)

    ReportViewPreference.create!(
      hotel:, user:, report_key: "daily_report_cashier_activity",
      visible_columns: %w[amount removed date_time]
    )
    expect(reader.visible_columns).to eq(%w[date_time amount])

    expect(reader.reset!).to eq(columns::DEFAULT_KEYS)
    expect(ReportViewPreference.where(hotel:, user:)).to be_empty
  end
end
