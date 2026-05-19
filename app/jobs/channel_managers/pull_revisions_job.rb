module ChannelManagers
  class PullRevisionsJob < ApplicationJob
    queue_as :default
    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    def perform
      client = Channex::Client.new
      page = 1
      per_page = 100

      loop do
        # The feed returns revisions that haven't been acknowledged yet
        # We order by oldest first to process in correct chronological order
        response = client.get("/booking_revisions/feed", {
          "order[inserted_at]" => "asc",
          "page" => page,
          "limit" => per_page
        })

        if response[:error] || response["error"]
          if response[:retryable] || response["retryable"]
            raise Channex::Client::RetryableRequestError, "Pull revisions retryable failure: #{response[:details] || response['details'] || response}"
          end

          Rails.logger.error("Channel Manager Pull Revisions Failed: #{response}")
          break
        end

        revisions = response["data"]
        break if revisions.blank?

        revisions.each do |revision|
          attributes = revision["attributes"] || revision
          property_id = attributes["property_id"] || revision["property_id"]

          # Find hotel mapping
          mapping = ChannelMapping.find_by(provider: "channex", external_id: property_id, mappable_type: "Hotel")
          next unless mapping

          # We enqueue a job for each revision to process and acknowledge it independently
          ChannelManagers::IngestRevisionJob.perform_later(mapping.mappable_id, revision["id"])
        end

        # Check for next page if meta pagination info is provided
        meta = response["meta"]
        if meta && meta["pagination"]
          current_page = meta.dig("pagination", "current_page")
          total_pages = meta.dig("pagination", "total_pages")
          break if current_page >= total_pages
          page += 1
        else
          # Fallback: if we got exactly per_page, there might be more, but feed usually drains as we ack.
          # However, PullRevisionsJob enqueues jobs that will ack LATER.
          # So the feed will NOT drain immediately. We must use pagination.
          break if revisions.size < per_page
          page += 1
        end
      end
    end
  end
end
