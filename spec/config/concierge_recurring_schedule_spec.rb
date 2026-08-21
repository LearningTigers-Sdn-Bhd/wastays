# frozen_string_literal: true

require "rails_helper"
require "yaml"

# The sweep is the whole mechanism: a thread that has gone quiet is never
# touched again, so a check made on the next message would never run. If it is
# not scheduled, nothing closes anything.
RSpec.describe "Concierge recurring schedule" do
  subject(:schedule) do
    YAML.safe_load_file(Rails.root.join("config/recurring.yml"), aliases: true)
  end

  %w[production demo].each do |environment|
    it "sweeps stale conversations hourly in #{environment}" do
      task = schedule.fetch(environment).fetch("close_stale_conversations")

      expect(task).to eq(
        "class" => "Concierge::CloseStaleConversationsJob",
        "schedule" => "every hour at minute 24"
      )
    end
  end
end
