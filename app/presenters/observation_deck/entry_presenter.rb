# frozen_string_literal: true

module ObservationDeck
  class EntryPresenter
    SLOW_DURATION_MS = 1_000

    TYPE_ICONS = {
      "request" => "globe",
      "sql" => "database",
      "job" => "list-todo",
      "mail" => "mail",
      "api" => "waypoints"
    }.freeze

    attr_reader :entry

    def self.for(entries)
      entries = entries.to_a
      users = User.where(id: user_ids(entries)).index_by(&:id)
      entries.map { |entry| new(entry, users:) }
    end

    def self.user_ids(entries)
      entries.filter_map do |entry|
        Array(entry.tags).find { |tag| tag.start_with?("user:") }&.delete_prefix("user:")
      end
    end
    private_class_method :user_ids

    def initialize(entry, users: nil)
      @entry = entry
      @users = users || User.where(id: self.class.send(:user_ids, [ entry ])).index_by(&:id)
    end

    delegate :id, :entry_type, :request_id, :status, :duration, :path, :created_at, to: :entry

    def title
      case entry_type
      when "request"
        case path
        when /POST \/guest\/request_magic_link/ then "Guest login link requested"
        when /GET \/guest\/login/ then "Guest viewed login page"
        when /POST \/api\/v1\/bookings/ then "New booking attempt"
        when /POST \/webhooks\/channex/ then "Channex Webhook#{channel_id ? " (ID: #{channel_id})" : ""}"
        when /GET \/admin\/observation_deck/ then "Admin viewed Observation Deck"
        else "Web request: #{path.to_s.split.last}"
        end
      when "job" then "Background task: #{path.to_s.delete_suffix(" (Enqueued)")}"
      when "mail" then "Email sent: #{path}"
      when "sql" then "Database: #{path}"
      when "api"
        if path.to_s.include?("channex")
          "Channel manager update#{channel_id ? " (ID: #{channel_id})" : ""}"
        elsif path.to_s.include?("razorpay")
          "Payment gateway action (Razorpay)"
        else
          "External API call"
        end
      else
        entry_type.to_s.humanize
      end
    end

    def type_label = entry_type.to_s.capitalize
    def type_icon = TYPE_ICONS.fetch(entry_type, "activity")
    def error? = status.to_i >= 400
    def slow? = duration.to_f >= SLOW_DURATION_MS
    def status_label = status.presence || "—"
    def duration_label = "#{format("%.1f", duration.to_f)} ms"
    def timestamp_label = created_at.in_time_zone.strftime("%H:%M:%S")
    def date_label = created_at.in_time_zone.strftime("%d %b")
    def full_timestamp = created_at.in_time_zone.strftime("%d %b %Y, %H:%M:%S.%L %Z")
    def day = created_at.in_time_zone.to_date

    def day_label
      return "Today" if day == Time.zone.today
      return "Yesterday" if day == Time.zone.yesterday

      day.strftime("%A, %d %B %Y")
    end

    def identity
      return "Admin: #{user.name}" if user
      return "Booking ##{booking_id}" if booking_id

      "System / guest"
    end

    def context_rows
      [
        [ "Identity", identity ],
        ([ "Booking", "##{booking_id}" ] if booking_id),
        ([ "Request ID", request_id ] if trace?)
      ].compact
    end

    def metadata_rows
      return [] unless entry_type == "request"

      [
        [ "IP address", payload["remote_ip"].presence || "Unknown" ],
        [ "User agent", payload["user_agent"].presence || "Unknown" ]
      ]
    end

    def visible_tags
      tags.reject { |tag| tag.start_with?("user:", "booking:") }
    end

    def trace? = request_id.present? && request_id != "none"
    def current_analysis = entry.ai_analysis.presence&.with_indifferent_access
    def analyzable? = error? || slow?
    def exception_message = payload["exception"].presence || payload["exception_object"].presence
    def payload_kind = entry_type == "sql" ? :sql : (entry_type == "mail" ? :mail : :json)
    def payload_text = payload["sql"].to_s

    def json_payload
      JSON.pretty_generate(payload)
    rescue JSON::GeneratorError, TypeError
      "{}"
    end

    def mail_headers
      [
        [ "From", Array(payload["from"]).join(", ") ],
        [ "To", Array(payload["to"]).join(", ") ],
        [ "Subject", payload["subject"].to_s ],
        [ "Date", full_timestamp ]
      ]
    end

    def mail_html
      ActionController::Base.helpers.sanitize(
        payload["html_body"].to_s,
        tags: %w[a blockquote br code div em h1 h2 h3 h4 h5 h6 hr li ol p pre span strong table tbody td th thead tr ul],
        attributes: %w[href title]
      )
    end
    def mail_text = payload["text_body"].to_s

    private

    def tags = Array(entry.tags)
    def user
      @users[user_id.to_i] if user_id.present?
    end
    def user_id = tags.find { |tag| tag.start_with?("user:") }&.delete_prefix("user:")
    def booking_id = tags.find { |tag| tag.start_with?("booking:") }&.delete_prefix("booking:")
    def channel_id = tags.find { |tag| tag.start_with?("channex_id:") }&.delete_prefix("channex_id:")
    def payload = entry.payload.is_a?(Hash) ? entry.payload : {}
  end
end
