require "rails_helper"

RSpec.describe NightAudits::Execution::PersistFailure do
  it "is the default Run failure handler" do
    initializer = NightAudits::Run.instance_method(:initialize)

    expect(initializer.parameters).to include([ :key, :failure_handler ])
  end
end
