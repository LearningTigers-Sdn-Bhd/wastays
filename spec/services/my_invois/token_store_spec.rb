require "rails_helper"

RSpec.describe MyInvois::TokenStore, type: :service do
  describe ".fetch" do
    let(:key_args) do
      {
        tin: "C1234567890",
        environment: "sandbox",
        mode: "taxpayer",
        represented_taxpayer_tin: nil
      }
    end

    before { Rails.cache.clear }

    it "invalidates cached token when authentication fails" do
      Rails.cache.write(MyInvois::TokenStore.cache_key(**key_args), "stale-token")

      expect {
        described_class.fetch(**key_args) { raise MyInvois::Client::ApiError.new("Auth failed") }
      }.to raise_error(MyInvois::Client::ApiError, "Auth failed")

      expect(Rails.cache.read(MyInvois::TokenStore.cache_key(**key_args))).to be_nil
    end
  end
end
