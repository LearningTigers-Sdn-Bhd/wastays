require "rails_helper"

RSpec.describe Logs::PruneOldEntries do
  let(:now) { Time.zone.local(2026, 10, 1, 3, 0) }

  def mail_event(sent_at) = MailEvent.create!(mailer: "GuestMailer", sent_at: sent_at)
  def error_event(occurred_at) = ErrorEvent.create!(error_class: "StandardError", occurred_at: occurred_at)

  it "deletes mail events older than 90 days and keeps newer ones" do
    old = mail_event(now - 91.days)
    kept = mail_event(now - 89.days)

    result = described_class.call(now: now)

    expect(result[:mail_events]).to be >= 1
    expect(MailEvent.where(id: [ old.id, kept.id ])).to eq([ kept ])
  end

  it "deletes error events older than 30 days and keeps newer ones" do
    old = error_event(now - 31.days)
    kept = error_event(now - 29.days)

    result = described_class.call(now: now)

    expect(result[:error_events]).to be >= 1
    expect(ErrorEvent.where(id: [ old.id, kept.id ])).to eq([ kept ])
  end

  it "keeps a mail event that is older than the error period but newer than the mail period" do
    kept = mail_event(now - 60.days)

    described_class.call(now: now)

    expect(MailEvent.exists?(kept.id)).to be(true)
  end

  it "works in small batches" do
    3.times { mail_event(now - 100.days) }

    expect(described_class.call(now: now, batch_size: 2)[:mail_events]).to be >= 3
  end
end
