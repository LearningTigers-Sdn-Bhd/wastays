# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReportViewPreference do
  it "keeps one preference per user, hotel, and report" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    described_class.create!(
      hotel:,
      user:,
      report_key: "housekeeping_tasks",
      visible_columns: %w[room_number remarks]
    )
    duplicate = described_class.new(
      hotel:,
      user:,
      report_key: "housekeeping_tasks",
      visible_columns: %w[room_number]
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:report_key]).to be_present
  end
end
