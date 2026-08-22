# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Providers::UsageLog do
  let(:hotel) { build(:hotel, ai_provider_enabled: true, ai_provider_name: "claude", ai_provider_key: "test-key") }

  it "writes what the call cost" do
    response = instance_double(RubyLLM::Message, input_tokens: 1_400, output_tokens: 80, cached_tokens: 1_127)
    allow(Rails.logger).to receive(:info)

    described_class.call(response, hotel: hotel, stage: :loop)

    expect(Rails.logger).to have_received(:info).with(/loop provider=claude .*in=1400 out=80 cached=1127/)
  end

  # Every eval fixture reaches this through ScriptedChat, whose response is a
  # two-field Struct. A logger that raised here would take the whole suite
  # down, and it would take it down over bookkeeping.
  it "stays quiet when the response cannot report usage" do
    expect { described_class.call(Struct.new(:content).new("hi"), hotel: hotel, stage: :stylist) }
      .not_to raise_error
  end
end
