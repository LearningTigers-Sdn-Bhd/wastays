require "rails_helper"

RSpec.describe NightAudits::Evaluation::Warnings::OpenOperationalRequests do
  it "is registered as an audit warning" do
    expect(NightAudits::Evaluate::WARNINGS).to include(described_class)
  end
end
