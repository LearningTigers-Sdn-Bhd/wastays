# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::RecoverStaleIndexingJob do
  it "runs the stale-index recovery service" do
    service = instance_double(HotelKnowledges::RecoverStaleIndexing, call: nil)
    allow(HotelKnowledges::RecoverStaleIndexing).to receive(:new).and_return(service)

    described_class.perform_now

    expect(service).to have_received(:call)
  end

  it "uses the AI concierge queue" do
    expect(described_class.new.queue_name).to eq("ai_concierge")
  end
end
