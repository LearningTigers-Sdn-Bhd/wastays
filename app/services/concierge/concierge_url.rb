module Concierge
  class ConciergeUrl
    def self.for(hotel, host: ENV.fetch("APP_HOST", "wastays.com"), scheme: "https")
      "#{scheme}://#{host}/concierge/#{hotel.unique_id}/#{hotel.public_id}"
    end
  end
end
