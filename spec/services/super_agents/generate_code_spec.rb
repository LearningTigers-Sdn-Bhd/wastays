# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuperAgents::GenerateCode do
  it "makes a 6-character code from easy-to-read characters" do
    code = described_class.call

    expect(code).to match(/\A[A-HJ-NP-Z2-9]{6}\z/)
  end

  it "tries again when the code is already taken" do
    allow(User).to receive(:exists?).and_return(true, false)

    described_class.call

    expect(User).to have_received(:exists?).twice
  end
end
