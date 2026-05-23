require "rails_helper"

RSpec.describe FinancialObservabilityJob, type: :job do
  let(:hotel) { create(:hotel) }
  let!(:config) { create(:hotel_team_config, hotel: hotel, template_type: "financial_observability", frequency: 86400) }

  describe "#perform" do
    context "when an alert is due" do
      before do
        # Simulate an anomaly so report_worthy? is true
        allow(FinancialControls::EvaluateAnomalies).to receive(:call).and_return({
          unbalanced_folios: [ { id: 1 } ],
          audit_sync_lags: [],
          override_abuse: nil
        })
      end

      it "sends the email and updates last_alert_sent_at" do
        expect {
          described_class.new.perform
        }.to change { ActionMailer::Base.deliveries.count }.by(1)

        expect(config.reload.last_alert_sent_at).to be_present
      end

      it "throttles based on frequency" do
        described_class.new.perform

        # Second run immediately should not send another email
        expect {
          described_class.new.perform
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context "when no anomalies are found" do
      before do
        allow(FinancialControls::EvaluateAnomalies).to receive(:call).and_return({
          unbalanced_folios: [],
          audit_sync_lags: [],
          override_abuse: nil
        })
      end

      it "does not send an email" do
        expect {
          described_class.new.perform
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end
end
