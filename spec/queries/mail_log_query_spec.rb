require "rails_helper"

RSpec.describe MailLogQuery do
  let!(:old_sent) { MailEvent.create!(mailer: "GuestMailer", subject: "Welcome", recipients: "ann@example.com", status: "sent", sent_at: Time.zone.local(2026, 9, 1, 10)) }
  let!(:new_failed) { MailEvent.create!(mailer: "SystemMailer", subject: "Alert", recipients: "ops@example.com", status: "failed", sent_at: Time.zone.local(2026, 9, 20, 10)) }

  def result(params) = described_class.new(params, scope: MailEvent.where(id: [ old_sent.id, new_failed.id ])).call

  it "lists newest first" do
    expect(result({})).to eq([ new_failed, old_sent ])
  end

  it "filters by status and ignores unknown statuses" do
    expect(result(status: "failed")).to eq([ new_failed ])
    expect(result(status: "bogus")).to eq([ new_failed, old_sent ])
  end

  it "filters by recipient or subject" do
    expect(result(q: "ann@")).to eq([ old_sent ])
    expect(result(q: "alert")).to eq([ new_failed ])
  end

  it "filters by date range and ignores bad dates" do
    expect(result(start_date: "2026-09-01", end_date: "2026-09-02")).to eq([ old_sent ])
    expect(result(start_date: "2026-09-10")).to eq([ new_failed ])
    expect(result(end_date: "2026-09-10")).to eq([ old_sent ])
    expect(result(start_date: "nope", end_date: "nope")).to eq([ new_failed, old_sent ])
  end
end
