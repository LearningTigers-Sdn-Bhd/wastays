# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::MagicLinks::Issue do
  let(:guest) { create(:guest, email: "jasmine@example.com") }

  it "issues one portal token and queues the existing email" do
    result = nil

    expect {
      result = described_class.new(guest: guest, source: :concierge).call
    }.to have_enqueued_mail(GuestMailer, :magic_link)

    expect(result).to be_success
    expect(result.masked_email).to eq("j•••@example.com")
    expect(guest.reload.magic_token_digest).to be_present
  end

  it "replaces an expired token" do
    old_digest = Digest::SHA256.hexdigest(guest.generate_magic_token!)
    guest.update_column(:magic_token_expires_at, 1.minute.ago)

    result = described_class.new(guest: guest, source: :guest_portal).call

    expect(result).to be_success
    expect(guest.reload.magic_token_digest).not_to eq(old_digest)
  end

  it "returns the shared cooldown without sending another email" do
    guest.generate_magic_token!

    expect {
      @result = described_class.new(guest: guest, source: :concierge).call
    }.not_to have_enqueued_mail(GuestMailer, :magic_link)

    expect(@result.error_code).to eq(:cooldown)
    expect(@result.retry_after).to be_within(1.second).of(2.minutes.from_now)
  end

  it "rejects a guest without email" do
    guest.update_column(:email, nil)

    result = described_class.new(guest: guest, source: :concierge).call

    expect(result.error_code).to eq(:email_unavailable)
  end

  it "clears the token when the email cannot be queued" do
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(GuestMailer).to receive(:magic_link).and_return(delivery)
    allow(delivery).to receive(:deliver_later).and_raise(ActiveJob::EnqueueError)

    result = described_class.new(guest: guest, source: :concierge).call

    expect(result.error_code).to eq(:delivery_unavailable)
    expect(guest.reload.magic_token_digest).to be_nil
  end

  it "treats a rejected synchronous enqueue as unavailable" do
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: false)
    allow(GuestMailer).to receive(:magic_link).and_return(delivery)

    result = described_class.new(guest: guest, source: :concierge).call

    expect(result.error_code).to eq(:delivery_unavailable)
    expect(guest.reload.magic_token_digest).to be_nil
  end

  it "rejects an unknown request source" do
    expect {
      described_class.new(guest: guest, source: :unknown).call
    }.to raise_error(ArgumentError, /Unknown magic-link source/)
  end
end
