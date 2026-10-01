require "rails_helper"

RSpec.describe NotificationLogQuery do
  let(:hotel) { create(:hotel) }
  let!(:whatsapp) { create(:notification_delivery, hotel: hotel, channel: "whatsapp", status: "sent", created_at: Time.zone.local(2026, 9, 1, 10)) }
  let!(:email) { create(:notification_delivery, hotel: hotel, channel: "email") }
  let!(:alert) { create(:staff_notification, hotel: hotel, subject: create(:night_audit, hotel: hotel), title: "Audit stuck", created_at: Time.zone.local(2026, 9, 20, 10)) }

  it "defaults to the WhatsApp tab and ignores unknown tabs" do
    expect(described_class.new({}).tab).to eq("whatsapp")
    expect(described_class.new(tab: "bogus").tab).to eq("whatsapp")
  end

  it "lists WhatsApp deliveries only, never email" do
    expect(described_class.new(tab: "whatsapp").call).to eq([ whatsapp ])
  end

  it "lists staff alerts on the staff tab" do
    expect(described_class.new(tab: "staff").call).to eq([ alert ])
  end

  it "searches WhatsApp rows by type, booking token and guest" do
    expect(described_class.new(q: "check_in").call).to eq([ whatsapp ])
    expect(described_class.new(q: whatsapp.booking.confirmation_token).call).to eq([ whatsapp ])
    expect(described_class.new(q: "no-match-xyz").call).to be_empty
  end

  it "searches staff alerts by title and staff name" do
    expect(described_class.new(tab: "staff", q: "stuck").call).to eq([ alert ])
    expect(described_class.new(tab: "staff", q: alert.recipient.name).call).to eq([ alert ])
  end

  it "filters by date range" do
    expect(described_class.new(range: "2026-09-02/2026-09-30").call).to be_empty
    expect(described_class.new(tab: "staff", range: "2026-09-15/2026-09-30").call).to eq([ alert ])
  end
end
