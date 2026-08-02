require "rails_helper"

RSpec.describe NightAudits::Execution::ProcessBookings do
  it "runs no-show and due-out processing" do
    audit = create(:night_audit)
    no_shows = instance_double(OpenStruct)
    due_outs = instance_double(OpenStruct)
    allow(NightAudits::ProcessNoShowDetections).to receive(:call).and_return(no_shows)
    allow(NightAudits::DetectDueOuts).to receive(:call).and_return(due_outs)

    result = described_class.call(night_audit: audit, user: audit.performed_by_user)

    expect(result.no_shows).to be(no_shows)
    expect(result.due_outs).to be(due_outs)
  end
end
