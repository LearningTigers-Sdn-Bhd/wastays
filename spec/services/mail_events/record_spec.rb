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
end
