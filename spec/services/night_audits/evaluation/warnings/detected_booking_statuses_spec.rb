require "rails_helper"

RSpec.describe NightAudits::Evaluation::Warnings::DetectedBookingStatuses do
  it "is not registered because detected stays now require staff action" do
    expect(NightAudits::Evaluate::WARNINGS).not_to include(described_class)
  end
end
