# frozen_string_literal: true

require "rails_helper"

RSpec.describe MillionSendDelivery do
  let(:url) { "https://email-api.jesseltonpixel.com/emails" }
  let(:delivery) { described_class.new(api_key: "test-key") }
  let(:mail) do
    Mail.new do
      from "WAStays <noreply@wastays.com>"
      to "guest@example.com"
      subject "Hello"
      text_part { body "plain" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>html</p>"
      end
    end
  end

  it "posts the mail as JSON with bearer auth" do
    stub = stub_request(:post, url)
      .with(headers: { "Authorization" => "Bearer test-key" }) { |req|
        body = JSON.parse(req.body)
        body.values_at("from", "to", "subject", "html", "text") ==
          [ "WAStays <noreply@wastays.com>", [ "guest@example.com" ], "Hello", "<p>html</p>", "plain" ]
      }
      .to_return(status: 200, body: { id: "abc" }.to_json)

    expect(delivery.deliver!(mail)).to eq("id" => "abc")
    expect(stub).to have_been_requested
  end

  it "sends attachments base64-encoded and inline images with a content_id" do
    mail.attachments["a.pdf"] = "PDFDATA"
    mail.attachments.inline["logo.png"] = "PNGDATA"
    mail.attachments["logo.png"].url # what image_tag does in a template; assigns the cid
    stub = stub_request(:post, url).with { |req|
      atts = JSON.parse(req.body)["attachments"]
      atts.find { |a| a["filename"] == "a.pdf" }["content"] == Base64.strict_encode64("PDFDATA") &&
        atts.find { |a| a["filename"] == "logo.png" }["content_id"].present?
    }.to_return(status: 200, body: "{}")

    delivery.deliver!(mail)
    expect(stub).to have_been_requested
  end

  it "sends a single-part text-only mail (no multipart parts)" do
    text_only = Mail.new(from: "noreply@wastays.com", to: "guest@example.com", subject: "Plain", body: "just text")
    stub = stub_request(:post, url).with { |req|
      body = JSON.parse(req.body)
      body["text"] == "just text" && !body.key?("html")
    }.to_return(status: 200, body: "{}")

    delivery.deliver!(text_only)
    expect(stub).to have_been_requested
  end

  it "keeps non-ASCII text-only bodies as valid UTF-8" do
    text_only = Mail.new(from: "noreply@wastays.com", to: "guest@example.com", subject: "Refund — RM 50", body: "café ✓")
    text_only.content_type = "text/plain; charset=UTF-8"

    body = delivery.send(:payload_for, text_only)[:text]

    expect(body).to eq("café ✓")
    expect(body.encoding).to eq(Encoding::UTF_8)
  end

  it "sends the real text-only forgot-password email with its reset link" do
    reset_mail = OwnerPasswordResetMailer.forgot(create(:user), "TOKEN123")
    stub = stub_request(:post, url).with { |req|
      JSON.parse(req.body)["text"].to_s.include?("/owner-password-reset/TOKEN123")
    }.to_return(status: 200, body: "{}")

    delivery.deliver!(reset_mail.message)
    expect(stub).to have_been_requested
  end

  it "raises on API errors such as suppressed recipients" do
    stub_request(:post, url).to_return(status: 422, body: '{"name":"all_recipients_suppressed"}')

    expect { delivery.deliver!(mail) }
      .to raise_error(described_class::DeliveryError, /422.*all_recipients_suppressed/)
  end
end
