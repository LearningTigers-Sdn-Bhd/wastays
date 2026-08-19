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
    # `setting` is the filing hotel's e-invoice setting, carrying its own LHDN
    # credentials and chosen environment.
    def self.build(mode: :taxpayer, represented_taxpayer_tin: nil, setting: nil)
      if mock?(setting)
        MyInvois::MockClient.new(mode: mode, represented_taxpayer_tin: represented_taxpayer_tin)
      else
        MyInvois::Client.new(mode: mode, represented_taxpayer_tin: represented_taxpayer_tin, setting: setting)
      end
    end

    def self.mock?(setting = nil)
      return true if ENV["MYINVOIS_MOCK"] == "true"
      return true if setting&.api_environment == "mock"
      # A hotel that has not handed over its LHDN access cannot file for real.
      return true if setting.present? && !setting.api_credentials_ready?
      return false if setting&.api_credentials_ready?

      environment = Rails.application.credentials.dig(:myinvois, :environment)
      return true if environment == "mock"

      # Unconfigured must never mean "talk to the live tax authority". An
      # environment has to be chosen deliberately before anything is filed.
      environment.blank?
    end

    def self.sandbox?
      Rails.application.credentials.dig(:myinvois, :environment) == "sandbox" || mock?
    end
  end
end
