# frozen_string_literal: true

require "rails_helper"

RSpec.describe OwnerPasswordResetMailer do
  let(:user) { create(:user, name: "Aisha Rahman") }

  shared_examples "a branded reset email" do
    it "has text and HTML parts with the reset link and inline logo" do
      expect(mail.text_part.decoded).to include("/owner-password-reset/TOKEN123")
      html = mail.html_part.decoded
      expect(html).to include("/owner-password-reset/TOKEN123", "Set New Password", "Hello Aisha", "cid:")
      expect(mail.attachments.map(&:filename)).to include("long-logo.png")
      expect(mail.attachments["long-logo.png"]).to be_inline
    end
  end

  describe ".forgot" do
    let(:mail) { described_class.forgot(user, "TOKEN123") }

    it_behaves_like "a branded reset email"

    it "says the user requested it" do
      expect(mail.html_part.decoded).to include("We received a request")
    end
  end

  describe ".reset" do
    let(:hotel) { create(:hotel) }
    let(:mail) { described_class.reset(user, hotel, "TOKEN123") }

    it_behaves_like "a branded reset email"

    it "says an administrator requested it for the hotel" do
      expect(mail.html_part.decoded).to include("An administrator requested", hotel.name)
    end
  end
end
