# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "observation:prune" do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("observation:prune")
    Rake::Task["observation:prune"].reenable
  end

  it "delegates to the rolling-retention service" do
    allow(ObservationDeck::PruneEntries).to receive(:call).and_return(12)

    expect { Rake::Task["observation:prune"].invoke }
      .to output("Pruned 12 observation entries older than 7 days.\n").to_stdout

    expect(ObservationDeck::PruneEntries).to have_received(:call).once
  end
end
