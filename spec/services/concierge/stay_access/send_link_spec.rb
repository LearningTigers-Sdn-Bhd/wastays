require "rails_helper"

RSpec.describe Concierge::StayAccess::SendLink do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", guest_email: "ahmad@example.com")
  end

  def send_link(now: Time.current, reason: :check_in)
    described_class.new(booking: booking, reason: reason, now: now).call
  end

  it "creates the record and queues one mail" do
    expect { send_link }.to have_enqueued_mail(GuestMailer, :stay_link)

    record = booking.concierge_stay_accesses.live.first
    expect(record).to be_present
    expect(record.send_count).to eq(1)
    expect(record.link_sent_at).to be_present
  end

  it "masks the email in the answer" do
    expect(send_link.masked_email).to eq("a•••@example.com")
  end

  it "reuses the live record on a second send" do
    first = send_link.stay_access
    second = send_link(now: 1.minute.from_now).stay_access

    expect(second).to eq(first)
    expect(booking.concierge_stay_accesses.live.count).to eq(1)
  end

  it "stops after three sends in one hour" do
    3.times { |index| send_link(now: Time.current + index.minutes) }

    result = send_link(now: 4.minutes.from_now)

    expect(result.success?).to be false
    expect(result.error).to eq(described_class::COOLDOWN)
    expect(result.retry_after).to be_positive
  end

  it "sends again after the window closes" do
    3.times { |index| send_link(now: Time.current + index.minutes) }

    result = send_link(now: 2.hours.from_now)

    expect(result.success?).to be true
    expect(result.stay_access.send_count).to eq(1)
  end

  it "refuses a booking with no email" do
    booking.update_columns(guest_email: nil)

    result = described_class.new(booking: booking.reload).call

    expect(result.success?).to be false
    expect(result.error).to eq(described_class::NO_EMAIL)
  end

  it "refuses a booking that holds no stay page" do
    confirmed = create(:booking, hotel: hotel, status: "confirmed", guest_email: "a@b.com")

    result = described_class.new(booking: confirmed).call

    expect(result.success?).to be false
    expect(confirmed.concierge_stay_accesses).to be_empty
  end

  it "sends the stable stay URL and no login token" do
    send_link
    record = booking.concierge_stay_accesses.live.first
    mail = GuestMailer.stay_link(record, "ahmad@example.com")

    expect(mail.body.encoded).to include("stay/#{record.stay_access_id}")
    expect(mail.body.encoded).not_to include("/guest/verify")
    expect(mail.body.encoded).not_to include(booking.confirmation_token)
  end
end
