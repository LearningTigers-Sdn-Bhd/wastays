# frozen_string_literal: true

module MyInvois
  # Returns the appropriate client based on the configured environment.
  #
  # Use MyInvois::ClientFactory.build everywhere instead of
  # instantiating MyInvois::Client directly.
  #
  #   client = MyInvois::ClientFactory.build
  #   client.submit_documents(docs)
  #
  # Environments:
  #   "production" → MyInvois::Client (real API, live LHDN)
  #   "sandbox"    → MyInvois::Client (real API, preprod LHDN)
  #   "mock"       → MyInvois::MockClient (fake responses, no HTTP)
  #
  # Also activates mock if ENV["MYINVOIS_MOCK"] = "true" regardless of credentials.
  module ClientFactory
    def self.build
      if mock?
        MyInvois::MockClient.new
      else
        MyInvois::Client.new
      end
    end

    def self.mock?
      ENV["MYINVOIS_MOCK"] == "true" ||
        Rails.application.credentials.dig(:myinvois, :environment) == "mock"
    end

    def self.sandbox?
      Rails.application.credentials.dig(:myinvois, :environment) == "sandbox" || mock?
    end
  end
end
