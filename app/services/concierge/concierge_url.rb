module Concierge
  class ConciergeUrl
    def self.for(hotel, host: nil, scheme: nil, port: nil)
      options = Rails.application.config.action_mailer.default_url_options || {}
      use_configured_port = host.blank?
      host ||= options[:host].presence || "wastays.com"
      scheme ||= options[:protocol].presence || "https"
      port ||= options[:port].presence if use_configured_port

      authority = [ host, port ].compact.join(":")
      "#{scheme}://#{authority}/concierge/#{hotel.unique_id}/#{hotel.public_id}"
    end

    # The stable stay link. It identifies the stay and nothing else: no
    # confirmation code, and no session credential.
    def self.stay(hotel, stay_access_id, **options)
      "#{self.for(hotel, **options)}/stay/#{stay_access_id}"
    end
  end
end
