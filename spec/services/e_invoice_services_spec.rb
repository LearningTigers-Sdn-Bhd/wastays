# frozen_string_literal: true

require "rails_helper"

RSpec.describe "E-Invoice & MyInvois Services" do
  # EInvoice::Cancel
  describe EInvoice::Cancel do
    describe ".call" do
      # LHDN stamps validated_at when it validates, and the 72-hour
      # cancellation window runs from there.
      let(:submission) { create(:e_invoice_submission, status: "valid", validated_at: 1.hour.ago, uuid: "LHDN-UUID-1") }

      before do
        allow(MyInvois::ClientFactory).to receive(:build).and_return(
          instance_double(MyInvois::Client, cancel_document: { "success" => true })
        )
      end

      it "cancels the submission" do
        result = described_class.call(submission, reason: "Test cancellation")
        expect(result[:success]).to be true
        expect(submission.reload.status).to eq("cancelled")
      end
    end
  end

  # EInvoice::PhoneFormatter
  describe EInvoice::PhoneFormatter do
    include described_class

    describe "#format_phone" do
      it "formats Malaysian phone numbers starting with +" do
        expect(format_phone("+60123456789")).to eq("+60123456789")
      end

      it "formats phone numbers without + prefix" do
        expect(format_phone("0123456789")).to eq("+0123456789")
      end

      it "returns default for blank phone" do
        expect(format_phone("")).to eq(EInvoice::PhoneFormatter::DEFAULT_PHONE)
        expect(format_phone(nil)).to eq(EInvoice::PhoneFormatter::DEFAULT_PHONE)
      end
    end
  end

  # EInvoice::SubmissionContext
  describe EInvoice::SubmissionContext do
    describe ".for" do
      let(:hotel) { create(:hotel, status: "live", tin: "C9988776655", ssm_number: "202399887766") }
      # The hotel files under its own registration, so it needs a setting.
      let!(:setting) { create(:e_invoice_setting, hotel: hotel) }
      let(:booking) { create(:booking, hotel: hotel, fund_collector: "wastays") }

      before do
        allow(Rails.application.credentials).to receive(:myinvois).and_return(
          double(
            to_h: {
              tin: "C1234567890",
              brn: "202301012345",
              name: "Jesselton Pixel Sdn Bhd",
              phone: "+60111234567",
              email: "finance@wastays.com",
              city: "Kota Kinabalu",
              postal_code: "88000",
              state_code: "12",
              address: "123 Street"
            }
          )
        )
      end

      it "builds a context for a booking" do
        context = described_class.for(booking)
        expect(context).to be_a(EInvoice::SubmissionContext::Context)
        expect(context.booking).to eq(booking)
        expect(context.fund_collector).to eq("wastays")
      end
    end
  end

  # MyInvois::Client
  describe MyInvois::Client do
    before do
      allow(Rails.application.credentials).to receive(:dig).and_return(nil)
      allow(Rails.application.credentials).to receive_message_chain(:myinvois, :environment).and_return("production")
    end

    describe "#initialize" do
      it "accepts mode parameter" do
        client = described_class.new(mode: :taxpayer)
        expect(client).to be_a(described_class)
      end

      it "accepts represented_taxpayer_tin parameter" do
        client = described_class.new(mode: :intermediary, represented_taxpayer_tin: "C1234567890")
        expect(client).to be_a(described_class)
      end
    end
  end

  # MyInvois::ClientFactory
  describe MyInvois::ClientFactory do
    describe ".build" do
      it "returns a client instance" do
        allow(Rails.application.credentials).to receive(:myinvois).and_return(
          double(
            to_h: {
              tin: "C1234567890",
              brn: "202301012345",
              name: "Test Hotel",
              phone: "+60111234567",
              email: "test@hotel.com",
              city: "Kuala Lumpur",
              postal_code: "50000",
              state_code: "12",
              address: "123 Test Street"
            }
          )
        )
        # An explicit non-mock environment is required before a real client is
        # built; unconfigured deliberately falls back to the mock.
        setting = build(:e_invoice_setting, api_environment: "sandbox")
        client = described_class.build(setting: setting)
        expect(client).to be_a(MyInvois::Client)
      end
    end
  end
end
