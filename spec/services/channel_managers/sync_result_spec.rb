# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::SyncResult do
  it "builds a successful result and compacts task identifiers" do
    result = described_class.build(
      :partial_success,
      "Availability synced",
      warnings: "Pricing skipped",
      task_ids: { availability: "task-1", restrictions: nil }
    )

    expect(result).to be_success
    expect(result).not_to be_failure
    expect(result.warnings).to eq([ "Pricing skipped" ])
    expect(result.task_ids).to eq(availability: "task-1")
  end

  it "classifies unsupported pricing and failures" do
    unsupported = described_class.build(:unsupported_pricing, "Unsupported")
    failure = described_class.build(:failure, "Failed")

    expect(unsupported).to be_unsupported
    expect(unsupported).not_to be_success
    expect(failure).to be_failure
    expect(failure).not_to be_success
  end

  it "rejects unknown statuses" do
    expect { described_class.build(:unknown, "Unknown") }
      .to raise_error(ArgumentError, "Unknown channel sync status: unknown")
  end
end
