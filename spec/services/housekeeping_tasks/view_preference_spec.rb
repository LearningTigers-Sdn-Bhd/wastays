# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::ViewPreference do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }

  it "uses every column when the user has no saved preference" do
    expect(described_class.new(hotel:, user:).visible_columns).to eq(HousekeepingTasks::Columns::KEYS)
  end

  it "normalizes saved columns and ignores another user's preference" do
    other_user = create(:user, account: hotel.account)
    ReportViewPreference.create!(
      hotel:,
      user:,
      report_key: "housekeeping_tasks",
      visible_columns: %w[remarks stale room_number]
    )
    ReportViewPreference.create!(
      hotel:,
      user: other_user,
      report_key: "housekeeping_tasks",
      visible_columns: %w[pax]
    )

    expect(described_class.new(hotel:, user:).visible_columns).to eq(%w[room_number remarks])
  end

  it "falls back to every column when all saved keys are stale" do
    ReportViewPreference.create!(
      hotel:,
      user:,
      report_key: "housekeeping_tasks",
      visible_columns: %w[removed_column]
    )

    expect(described_class.new(hotel:, user:).visible_columns).to eq(HousekeepingTasks::Columns::KEYS)
  end
end
