module ChannelManagers
  class PullRevisionsJob < ApplicationJob
    queue_as :default

    def perform
      client = Channex::Client.new
      # The feed returns revisions that haven't been acknowledged yet
      response = client.get("/booking_revisions/feed")
      return unless response["data"]

      response["data"].each do |revision|
        property_id = revision["property_id"]
        # Find hotel mapping
        mapping = ChannelMapping.find_by(provider: "channex", external_id: property_id, mappable_type: "Hotel")
        next unless mapping

        # Reuse IngestRevisionJob but we already have data?
        # Actually IngestRevisionJob pulls full data which is safer.
        # But for efficiency we could pass data if feed has it all.
        # Channex feed usually has partial data, so pulling full revision is better.
        ChannelManagers::IngestRevisionJob.perform_later(mapping.mappable_id, revision["id"])
      end
    end
  end
end
