# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObservationDeck::PruneEntries, frozen_time: Time.zone.local(2026, 7, 24, 12) do
  it "deletes entries older than seven days and preserves the rolling window" do
    expired = create(:observation_entry, created_at: 7.days.ago - 1.second)
    boundary = create(:observation_entry, created_at: 7.days.ago)
    recent = create(:observation_entry, created_at: 1.day.ago)

    deleted_count = described_class.call

    expect(deleted_count).to eq(1)
    expect(ObservationEntry.exists?(expired.id)).to be(false)
    expect(ObservationEntry.exists?(boundary.id)).to be(true)
    expect(ObservationEntry.exists?(recent.id)).to be(true)
  end

  it "processes more than one batch" do
    expired_entries = create_list(:observation_entry, 3, created_at: 8.days.ago)
    deletes = []

    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      deletes << payload[:sql] if payload[:sql].start_with?("DELETE FROM \"observation_entries\"")
    end

    begin
      deleted_count = described_class.call(batch_size: 2)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    expect(deleted_count).to eq(3)
    expect(deletes.size).to eq(2)
    expect(ObservationEntry.where(id: expired_entries.map(&:id))).to be_empty
  end
end
