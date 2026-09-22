module Concierge
  class ConciergeUrl
    def self.for(hotel, host: ENV.fetch("APP_HOST", "wastays.com"), scheme: "https")
      "#{scheme}://#{host}/concierge/#{hotel.unique_id}/#{hotel.public_id}"
    end

    # The stable stay link. It identifies the stay and nothing else: no
    # confirmation code, and no session credential.
    def self.stay(hotel, stay_access_id, **options)
      "#{self.for(hotel, **options)}/stay/#{stay_access_id}"
    end
  end
end
