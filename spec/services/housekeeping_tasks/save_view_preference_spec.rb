# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::SaveViewPreference do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }

  it "saves allowed columns in canonical order" do
    result = described_class.new(
      hotel:,
      user:,
      visible_columns: %w[remarks unknown room_number]
    ).call

    expect(result).to be_success
    expect(result.visible_columns).to eq(%w[room_number remarks])
    expect(result.preference.visible_columns).to eq(%w[room_number remarks])
  end

  it "rejects a selection without an allowed column" do
    result = described_class.new(hotel:, user:, visible_columns: %w[unknown]).call

    expect(result).not_to be_success
    expect(result.error).to eq("Keep at least one column visible.")
    expect(ReportViewPreference.where(hotel:, user:)).to be_empty
  end
end
