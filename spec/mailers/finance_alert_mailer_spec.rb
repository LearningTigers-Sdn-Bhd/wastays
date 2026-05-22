require "rails_helper"

RSpec.describe FinanceAlertMailer, type: :mailer do
  describe "daily_digest" do
    let(:hotel) { create(:hotel, name: "Grand Budapest") }
    let(:config) { create(:hotel_team_config, hotel: hotel, emails: "finance@budapest.com") }
    let(:anomalies) do
      {
        unbalanced_folios: [ { confirmation_token: "WS-123", guest_name: "Gustave", balance: 150.0 } ],
        audit_sync_lags: [ { business_date: Date.yesterday, status: "open", lag_days: 1 } ],
        override_abuse: { count: 10, latest_actors: [ "Zero" ] }
      }
    end
    let(:mail) { described_class.daily_digest(config, anomalies) }

    it "renders the headers" do
      expect(mail.subject).to include("Daily Observability Digest - Grand Budapest")
      expect(mail.to).to eq([ "finance@budapest.com" ])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include("Unbalanced Folios")
      expect(mail.body.encoded).to include("WS-123")
      expect(mail.body.encoded).to include("Grand Budapest")
    end
  end
end
