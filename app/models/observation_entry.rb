class ObservationEntry < ApplicationRecord
  def human_title
    case entry_type
    when "request"
      case path
      when /POST \/guest\/request_magic_link/ then "Guest login link requested"
      when /GET \/guest\/login/ then "Guest viewed login page"
      when /POST \/api\/v1\/bookings/ then "New booking attempt"
      when /POST \/webhooks\/channex/
        ch_id = tags.find { |t| t.start_with?("channex_id:") }&.split(":")&.last
        "Channex Webhook #{ch_id ? "(ID: #{ch_id})" : ""}"
      when /GET \/admin\/observation_deck/ then "Admin viewed observation deck"
      else "Web Request: #{path.split(' ').last}"
      end
    when "job"
      "Background Task: #{path.gsub(' (Enqueued)', '')}"
    when "mail"
      "Email Sent: #{path}"
    when "sql"
      "Database: #{path}"
    when "api"
      if path.include?("channex")
        ch_id = tags.find { |t| t.start_with?("channex_id:") }&.split(":")&.last
        "Channel Manager Update #{ch_id ? "(ID: #{ch_id})" : "(Channel Manager)"}"
      elsif path.include?("razorpay")
        "Payment Gateway Action (Razorpay)"
      else
        "External API Call"
      end
    else
      entry_type.titleize
    end
  end

  def human_identity
    user_tag = tags.find { |t| t.start_with?("user:") }
    if user_tag
      user = User.find_by(id: user_tag.split(":").last)
      return "Admin: #{user.name}" if user
    end

    booking_tag = tags.find { |t| t.start_with?("booking:") }
    return "Booking ##{booking_tag.split(':').last}" if booking_tag

    "System / Guest"
  end
end
