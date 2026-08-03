require "rails_helper"

RSpec.describe NightAudits::Execution::FinalizeAudit do
  it "is the default Run finalizer" do
    initializer = NightAudits::Run.instance_method(:initialize)

    expect(initializer.parameters).to include([ :key, :finalizer ])
  end
end
