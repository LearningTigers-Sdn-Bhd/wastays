module ChannelManagers
  class PullRevisionsJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform
      client = Channex::Client.new
      # The feed returns revisions that haven't been acknowledged yet
      response = client.get("/booking_revisions/feed")
      if response[:error] || response["error"]
        if response[:retryable] || response["retryable"]
          raise Channex::Client::RetryableRequestError, "Pull revisions retryable failure: #{response[:details] || response['details'] || response}"
        end

        Rails.logger.error("Channel Manager Pull Revisions Failed: #{response}")
        return
      end

      return unless response["data"]

      response["data"].each do |revision|
        property_id = revision["property_id"]
        # Find hotel mapping
        mapping = ChannelMapping.find_by(provider: "channex", external_id: property_id, mappable_type: "Hotel")
        next unless mapping

        # Reuse IngestRevisionJob but we already have data?
        # Actually IngestRevisionJob pulls full data which is safer.
        # But for efficiency we could pass data if feed has it all.
        # Channel Manager feed usually has partial data, so pulling full revision is better.
        ChannelManagers::IngestRevisionJob.perform_later(mapping.mappable_id, revision["id"])
      end
    end
  end
end
