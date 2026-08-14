# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::SyncJob, type: :job do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let(:adapter) { instance_double(ChannelManagers::ChannexAdapter) }
  let(:range) { Date.current..(Date.current + 1.day) }

  before do
    allow(ChannelManagers::SyncOrchestrator).to receive(:adapter_for).with(hotel).and_return(adapter)
  end

  def perform
    described_class.new.perform(hotel.id, range.first, range.last)
  end

  it "does not retry terminal unsupported pricing" do
    allow(adapter).to receive(:push_ari).and_return(
      ChannelManagers::SyncResult.build(:unsupported_pricing, "occupancy ladder incomplete")
    )

    expect { perform }.not_to raise_error
  end

  it "does not retry validation warnings without changed input" do
    allow(adapter).to receive(:push_ari).and_return(
      ChannelManagers::SyncResult.build(:failure, "rejected", warnings: [ "invalid rate" ])
    )

    expect { perform }.not_to raise_error
  end

  it "lets retryable transport failures reach Active Job retry handling" do
    allow(adapter).to receive(:push_ari).and_raise(Channex::Client::RetryableRequestError, "HTTP 503")

    expect { perform }.to raise_error(Channex::Client::RetryableRequestError, "HTTP 503")
  end

  it "accepts partial and availability-only outcomes" do
    [ :partial_success, :availability_only ].each do |status|
      allow(adapter).to receive(:push_ari).and_return(ChannelManagers::SyncResult.build(status, status.to_s))
      expect { perform }.not_to raise_error
    end
  end

  it "does not contact the adapter while the property is in training" do
    hotel.update!(status: "ready_to_launch", training_started_at: Time.current)

    perform

    expect(ChannelManagers::SyncOrchestrator).not_to have_received(:adapter_for)
  end
end
