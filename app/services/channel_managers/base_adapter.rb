module ChannelManagers
  class BaseAdapter
    def initialize(hotel:)
      @hotel = hotel
    end

    def onboard_hotel
      raise NotImplementedError
    end

    def push_ari(date_range:)
      raise NotImplementedError
    end

    def ingest_booking(payload:)
      raise NotImplementedError
    end

    private

    def mapping_for(mappable)
      mappable.channel_mapping || mappable.create_channel_mapping(provider: provider_name, external_id: "pending")
    end

    def provider_name
      raise NotImplementedError
    end
  end
end
