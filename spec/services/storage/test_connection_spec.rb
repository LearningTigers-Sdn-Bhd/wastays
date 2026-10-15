# frozen_string_literal: true

require "rails_helper"

RSpec.describe Storage::TestConnection do
  let(:client) { Aws::S3::Client.new(stub_responses: true) }

  def service(**overrides)
    described_class.new(
      access_key_id: "r2-access",
      secret_access_key: "r2-secret",
      bucket: "wastays-production",
      endpoint: "https://account.r2.cloudflarestorage.com",
      region: "auto",
      **overrides
    )
  end

  before { allow(Aws::S3::Client).to receive(:new).and_return(client) }

  describe ".normalize_endpoint" do
    it "takes the bucket off the end of a pasted bucket URL" do
      normalized = described_class.normalize_endpoint(
        "https://account.r2.cloudflarestorage.com/wastays-production",
        "wastays-production"
      )

      expect(normalized).to eq("https://account.r2.cloudflarestorage.com")
    end

    it "leaves an account host alone" do
      normalized = described_class.normalize_endpoint("https://account.r2.cloudflarestorage.com", "wastays-production")

      expect(normalized).to eq("https://account.r2.cloudflarestorage.com")
    end

    it "leaves the endpoint alone when no bucket is given" do
      normalized = described_class.normalize_endpoint("https://account.r2.cloudflarestorage.com/x", "")

      expect(normalized).to eq("https://account.r2.cloudflarestorage.com/x")
    end
  end

  it "reports each missing setting before it makes a request" do
    expect(service(bucket: "").call.message).to eq("Bucket name is missing.")
    expect(service(endpoint: "").call.message).to eq("Endpoint URL is missing.")
    expect(service(access_key_id: "").call.message).to eq("Access key ID is missing.")
    expect(service(secret_access_key: "").call.message).to eq("Secret access key is missing.")
  end

  it "lists one object and names the bucket on success" do
    expect(client).to receive(:list_objects_v2).with(bucket: "wastays-production", max_keys: 1).and_call_original

    result = service.call

    expect(result).to be_success
    expect(result.message).to eq("Connected to the R2 bucket wastays-production.")
  end

  it "normalizes a pasted bucket URL before it connects" do
    expect(Aws::S3::Client).to receive(:new)
      .with(hash_including(endpoint: "https://account.r2.cloudflarestorage.com"))
      .and_return(client)

    service(endpoint: "https://account.r2.cloudflarestorage.com/wastays-production").call
  end

  it "reports an S3 error instead of raising" do
    allow(client).to receive(:list_objects_v2).and_raise(
      Aws::S3::Errors::AccessDenied.new(nil, "Access Denied")
    )

    result = service.call

    expect(result).not_to be_success
    expect(result.message).to eq("Connection failed: Access Denied")
  end

  it "reports any other error instead of raising" do
    allow(client).to receive(:list_objects_v2).and_raise(SocketError, "no such host")

    result = service.call

    expect(result).not_to be_success
    expect(result.message).to eq("An error occurred: no such host")
  end

  it "falls back to the saved settings when nothing is passed" do
    AppConfig.set("r2_access_key_id", "stored-access")
    AppConfig.set("r2_secret_access_key", "stored-secret")
    AppConfig.set("r2_bucket", "stored-bucket")
    AppConfig.set("r2_endpoint", "https://stored.r2.cloudflarestorage.com")

    expect(Aws::S3::Client).to receive(:new)
      .with(hash_including(access_key_id: "stored-access", region: "auto"))
      .and_return(client)

    expect(described_class.new.call.message).to eq("Connected to the R2 bucket stored-bucket.")
  end

  it "treats an empty field as empty rather than reading the saved value" do
    AppConfig.set("r2_bucket", "stored-bucket")

    expect(service(bucket: "").call.message).to eq("Bucket name is missing.")
  end
end
