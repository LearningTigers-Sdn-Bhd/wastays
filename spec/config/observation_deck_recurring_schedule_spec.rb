# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "Observation Deck recurring schedule" do
  subject(:schedule) do
    YAML.safe_load_file(Rails.root.join("config/recurring.yml"), aliases: true)
  end

  %w[production demo].each do |environment|
    it "schedules the pruning job daily at 3 AM in #{environment}" do
      task = schedule.fetch(environment).fetch("prune_observation_entries")

      expect(task).to eq(
        "class" => "ObservationDeck::PruneEntriesJob",
        "schedule" => "at 3am every day"
      )
    end
  end
end
