# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::ReachableChannels do
  it "keeps every channel the guest has an address for" do
    booking = build(:booking, guest_email: "guest@example.com", guest_phone: "+60123456789")

    expect(described_class.for(booking, %w[whatsapp email])).to eq(%w[whatsapp email])
  end

  it "drops email when the booking has no email" do
    booking = build(:booking, guest_email: nil, guest_phone: "+60123456789")

    expect(described_class.for(booking, %w[whatsapp email])).to eq(%w[whatsapp])
  end

  it "drops WhatsApp when the booking has no phone" do
    booking = build(:booking, guest_email: "guest@example.com", guest_phone: nil)

    expect(described_class.for(booking, %i[whatsapp email])).to eq(%w[email])
  end

  it "keeps channels that need no guest address" do
    booking = build(:booking, guest_email: nil, guest_phone: nil)

    expect(described_class.reachable?(booking, "webhook")).to be(true)
  end
end
