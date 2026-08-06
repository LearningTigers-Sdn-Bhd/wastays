# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObservationDeck::PruneEntriesJob, type: :job do
  it "delegates pruning and logs the deleted count" do
    allow(ObservationDeck::PruneEntries).to receive(:call).and_return(42)
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(ObservationDeck::PruneEntries).to have_received(:call).once
    expect(Rails.logger).to have_received(:info)
      .with("[ObservationDeck] Pruned 42 entries older than 7 days.")
  end

  it "allows pruning failures to propagate" do
    allow(ObservationDeck::PruneEntries).to receive(:call)
      .and_raise(ActiveRecord::StatementInvalid, "database unavailable")

    expect { described_class.perform_now }
      .to raise_error(ActiveRecord::StatementInvalid, "database unavailable")
  end
end
