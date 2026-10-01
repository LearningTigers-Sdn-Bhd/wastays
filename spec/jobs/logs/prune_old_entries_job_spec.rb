require "rails_helper"

RSpec.describe Logs::PruneOldEntriesJob, type: :job do
  it "prunes and logs the deleted counts" do
    allow(Logs::PruneOldEntries).to receive(:call).and_return(mail_events: 4, error_events: 2)
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(Logs::PruneOldEntries).to have_received(:call).once
    expect(Rails.logger).to have_received(:info).with("[Logs] Pruned 4 mail events and 2 error events.")
  end

  it "is scheduled every day in production and demo" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))

    %w[production demo].each do |environment|
      expect(config.dig(environment, "prune_log_entries")).to include("class" => "Logs::PruneOldEntriesJob", "schedule" => "at 3:30am every day")
    end
  end
end
