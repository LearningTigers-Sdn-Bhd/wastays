require "rails_helper"

RSpec.describe AiConciergeV3::ProspectNotFoundError do
  it "is a StandardError" do
    expect(described_class.superclass).to eq(StandardError)
  end

  it "can be raised and rescued" do
    result = catch(:raised) do
      begin
        raise described_class, "not found"
      rescue described_class => e
        throw :raised, e.message
      end
    end

    expect(result).to eq("not found")
  end
end
