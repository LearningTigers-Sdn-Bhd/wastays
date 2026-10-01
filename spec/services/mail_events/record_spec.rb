require "rails_helper"

RSpec.describe MailEvents::Record do
  let(:payload) do
    { mailer: "GuestMailer", action: "booking_confirmation", subject: "Your booking",
      to: [ "guest@example.com" ], cc: [ "cc@example.com" ], bcc: nil }
  end

  it "records a sent email" do
    event = described_class.call(payload: payload)

    expect(event).to have_attributes(
      mailer: "GuestMailer", mail_action: "booking_confirmation", subject: "Your booking",
      recipients: "guest@example.com, cc@example.com", status: "sent", error_message: nil
    )
  end

  it "records a failed email with its error" do
    event = described_class.call(payload: payload.merge(exception_object: StandardError.new("SMTP down")))

    expect(event).to have_attributes(status: "failed", error_message: "SMTP down")
  end

  it "does not raise when the record cannot be saved" do
    expect(described_class.call(payload: {})).to be_nil
  end

  it "records mail that ActionMailer delivers" do
    expect { SystemMailer.observability_test("ops@example.com").deliver_now }
      .to change(MailEvent, :count).by(1)
    expect(MailEvent.recent_first.first).to have_attributes(mailer: "SystemMailer", recipients: "ops@example.com", status: "sent")
  end

  describe "body" do
    def record(mail) = described_class.call(payload: payload.merge(mail: mail.encoded))

    it "stores the text part of a multipart email" do
      mail = Mail.new do
        to "guest@example.com"
        text_part { body "Hello guest" }
        html_part { content_type "text/html; charset=UTF-8"; body "<p>Hello <b>guest</b></p>" }
      end

      expect(record(mail).body).to eq("Hello guest")
    end

    it "turns an html-only email into plain text" do
      mail = Mail.new(to: "guest@example.com", content_type: "text/html; charset=UTF-8", body: "<p>Hello <b>guest</b></p>")

      expect(record(mail).body).to eq("Hello guest")
    end

    it "stores a plain email as it is" do
      expect(record(Mail.new(to: "guest@example.com", body: "Line one")).body).to eq("Line one")
    end

    it "keeps the event when the body cannot be read" do
      expect(described_class.call(payload: payload.merge(mail: nil)).body).to be_nil
    end
  end
end
