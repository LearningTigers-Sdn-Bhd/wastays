require "rails_helper"

RSpec.describe EInvoiceSubmission, type: :model do
  describe "#validation_url" do
    let(:hotel) { create(:hotel) }
    let(:booking) { create(:booking, hotel: hotel) }
    let(:submission) do
      EInvoiceSubmission.new(
        hotel: hotel,
        booking: booking,
        uuid: "12345-uuid",
        long_id: "67890-longid"
      )
    end

    context "when credentials environment is sandbox" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:myinvois, :environment).and_return("sandbox")
      end

      it "returns the preprod validation url" do
        expect(submission.validation_url).to eq("https://preprod.myinvois.hasil.gov.my/12345-uuid/share/67890-longid")
      end
    end

    context "when credentials environment is production" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:myinvois, :environment).and_return("production")
      end

      it "returns the production validation url" do
        expect(submission.validation_url).to eq("https://myinvois.hasil.gov.my/12345-uuid/share/67890-longid")
      end
    end
  end
end
