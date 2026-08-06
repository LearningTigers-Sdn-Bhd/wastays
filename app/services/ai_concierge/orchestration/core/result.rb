module AiConcierge
  module Orchestration
    module Core
      class Result
    attr_reader :payload, :error, :status

    def self.success(payload:)
      new(success: true, payload: payload)
    end

    def self.failure(error:, status:)
      new(success: false, error: error, status: status)
    end

    def initialize(success:, payload: nil, error: nil, status: nil)
      @success = success
      @payload = payload
      @error = error
      @status = status
    end

    def success?
      @success
    end
      end
    end
  end
end
