# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookDeliveryJob, type: :job do
  let(:url) { "https://example.com/webhook" }
  let(:payload) { { guest_name: "Aisyah" } }

  def stub_response(code)
    http = instance_double(Net::HTTP, "use_ssl=" => true, "open_timeout=" => true, "read_timeout=" => true)
    allow(http).to receive(:request).and_return(double(code: code.to_s))
    allow(Net::HTTP).to receive(:new).and_return(http)
    http
  end

  it "posts the event, when it was sent, and the payload" do
    http = stub_response(200)

    described_class.new.perform(url, "Relay", "concierge_staff_reply", payload)

    expect(http).to have_received(:request) do |request|
      body = JSON.parse(request.body)
      expect(body["event"]).to eq("concierge_staff_reply")
      expect(body["sent_at"]).to be_present
      expect(body["data"]).to eq("guest_name" => "Aisyah")
    end
  end

  it "treats every 2xx as delivered" do
    stub_response(204)

    expect { described_class.new.perform(url, "Relay", "test_event", payload) }.not_to raise_error
  end

  # The endpoint understood and said no. Sending it again unchanged gets the
  # same no.
  it "does not retry a refusal" do
    stub_response(422)

    expect { described_class.new.perform(url, "Relay", "test_event", payload) }.not_to raise_error
  end

  it "raises on a broken endpoint so the queue retries it" do
    stub_response(500)

    expect { described_class.new.perform(url, "Relay", "test_event", payload) }
      .to raise_error(described_class::DeliveryFailed, /HTTP 500/)
  end

  it "lets a network error surface for the same reason" do
    allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

    expect { described_class.new.perform(url, "Relay", "test_event", payload) }
      .to raise_error(Errno::ECONNREFUSED)
  end

  # The point of the whole split: a failure schedules another attempt instead
  # of being logged and forgotten.
  it "schedules another attempt rather than dropping the event" do
    stub_response(500)

    expect { described_class.perform_now(url, "Relay", "test_event", payload) }
      .to have_enqueued_job(described_class).with(url, "Relay", "test_event", payload)
  end

  it "does not schedule another attempt after a refusal" do
    stub_response(422)

    expect { described_class.perform_now(url, "Relay", "test_event", payload) }
      .not_to have_enqueued_job(described_class)
  end
end
