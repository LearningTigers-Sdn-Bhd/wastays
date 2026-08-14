module Concierge
  class ConciergeUrl
    def self.for(hotel, host: ENV.fetch("APP_HOST", "wastays.com"), scheme: "https")
      "#{scheme}://#{host}/concierge/#{hotel.to_param}"
    end
  end
end
