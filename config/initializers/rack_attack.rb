class Rack::Attack
  throttle("ai_concierge/api_key", limit: 60, period: 1.minute) do |req|
    if req.path.start_with?("/api/v1/hotels/") && req.path.end_with?("/ai_concierge/inquiries") && req.post?
      req.env["HTTP_AUTHORIZATION"]&.split(" ")&.last
    end
  end

  throttle("ai_concierge/ip", limit: 20, period: 1.minute) do |req|
    if req.path.start_with?("/api/v1/hotels/") && req.path.end_with?("/ai_concierge/inquiries") && req.post?
      req.ip
    end
  end

  throttle("concierge/booking_link/ip", limit: 10, period: 1.minute) do |req|
    booking_link_path = req.path.match?(%r{\A/concierge/[^/]+/chat/booking\z})
    req.ip if req.post? && booking_link_path
  end
end
