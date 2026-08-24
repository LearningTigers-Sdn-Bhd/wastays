# frozen_string_literal: true

require "rails_helper"

RSpec.describe MyInvois::Client::ApiError do
  # The distinction decides whether a document is retried or written off, so
  # it is worth pinning down explicitly.
  describe "#transient?" do
    it "treats LHDN server faults as retryable" do
      expect(described_class.new("boom", code: "500").transient?).to be(true)
      expect(described_class.new("boom", code: "503").transient?).to be(true)
    end

    it "treats rate limiting and request timeout as retryable" do
      expect(described_class.new("slow down", code: "429").transient?).to be(true)
      expect(described_class.new("timeout", code: "408").transient?).to be(true)
    end

    it "treats validation and auth rejections as permanent" do
      # Retrying these just repeats the same rejection.
      expect(described_class.new("bad doc", code: "400").transient?).to be(false)
      expect(described_class.new("no auth", code: "401").transient?).to be(false)
      expect(described_class.new("forbidden", code: "403").transient?).to be(false)
    end

    it "treats a configuration error with no status as permanent" do
      expect(described_class.new("credentials missing").transient?).to be(false)
    end
  end

  it "always treats a transport failure as retryable" do
    expect(MyInvois::Client::TransportError.new("connection reset").transient?).to be(true)
  end
end
