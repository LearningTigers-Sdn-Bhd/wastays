class Rack::Attack
  throttle("forgot_password/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/forgot-password"
  end

  throttle("forgot_password/email", limit: 3, period: 1.hour) do |req|
    req.params["email"].to_s.strip.downcase.presence if req.post? && req.path == "/forgot-password"
  end

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
