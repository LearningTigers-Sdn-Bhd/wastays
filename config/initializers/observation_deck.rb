# Observation Deck Instrumentation Initializer

# Guard: Disable in test environment to avoid transaction conflicts and boot noise
return if Rails.env.test?

# Guard: Disable instrumentation during migrations or database setup
# This prevents PG::UndefinedTable errors when the system is preparing the database
if defined?(Rake) && Rake.respond_to?(:application)
  begin
    return if Rake.application.top_level_tasks.any? { |t| t.include?("db:") }
  rescue StandardError
    # Ignore errors accessing rake tasks during boot
  end
end

# Helper to deeply scrub sensitive data
# We explicitly remove :email from the global filters for the Observation Deck so devs can debug user issues
OBSERVATION_SCRUBBER = ActiveSupport::ParameterFilter.new(
  (Rails.application.config.filter_parameters - [ :email ]) + [ :credit_card, :cvv, :passport, :ssn ]
)

# Helper to store entries (buffered for requests, immediate for jobs)
def capture_observation_entry(entry_data)
  entry_data[:request_id] = entry_data[:request_id].presence || Current.request_id || "none"

  if Current.respond_to?(:observation_buffer) && Current.observation_buffer.is_a?(Array)
    Current.observation_buffer << entry_data
  else
    # Outside of a request (e.g., background job), save immediately
    begin
      # Safety check: skip if the table hasn't been created yet (migration phase)
      return unless ActiveRecord::Base.connection.data_source_exists?("observation_entries")

      ObservationEntry.create!(entry_data)
    rescue ActiveRecord::StatementInvalid => e
      # Silently ignore if table doesn't exist yet
      return if e.message.include?("relation \"observation_entries\" does not exist")
      Rails.logger.error "[ObservationDeck] Failed to log entry: #{e.message}"
    rescue => e
      Rails.logger.error "[ObservationDeck] Failed to log entry: #{e.message}"
    end
  end
end

# Request Watcher
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  status = payload[:status].to_i
  path = payload[:path]

  # Guard: Ignore all internal, health check, and dev noise
  next if path.start_with?("/admin/observation_deck", "/up", "/rails/", "/hotwire-livereload")

  # Sampling Strategy: 100% Errors/Slow, 10% Success (100% in dev)
  is_error = status >= 400
  is_slow = event.duration > 1000
  is_sampled = Rails.env.development? ? true : rand < 0.1

  if is_error || is_slow || is_sampled
    tags = []
    if Current.respond_to?(:user_id) && Current.user_id.present?
      tags << "user:#{Current.user_id}"
    end

    if payload[:params].present?
      booking_id = payload[:params]["booking_id"] || payload[:params]["id"] if payload[:params]["controller"]&.include?("bookings")
      tags << "booking:#{booking_id}" if booking_id.present?

      # Extract Channex Webhook IDs
      if path.include?("webhooks/channex")
        channex_id = payload[:params]["id"] || payload[:params].dig("payload", "revision_id")
        tags << "channex_id:#{channex_id}" if channex_id.present?
      end
    end

    # Use raw parameters from the request object to bypass Rails' automatic pre-filtering
    # This allows OUR OBSERVATION_SCRUBBER (which allows email) to handle the filtering.
    request = payload[:request]
    raw_params = if request
      request.request_parameters.merge(request.query_parameters)
    else
      payload[:params] || {}
    end

    capture_observation_entry({
      entry_type: "request",
      request_id: payload[:request_id].presence || Current.request_id || "none",
      status: status,
      duration: event.duration,
      path: "#{payload[:method]} #{payload[:path]}",
      tags: tags.uniq,
      payload: OBSERVATION_SCRUBBER.filter({
        params: raw_params.except("controller", "action", "authenticity_token"),
        view_runtime: payload[:view_runtime],
        db_runtime: payload[:db_runtime],
        format: payload[:format],
        controller: payload[:controller],
        action: payload[:action],
        remote_ip: payload[:request]&.remote_ip,
        user_agent: payload[:request]&.user_agent
      })
    })
  end
end

# Job Watcher (Catch-all for debug)
ActiveSupport::Notifications.subscribe(/active_job/) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "[ObservationDeck] Job event: #{event.name} for #{event.payload[:job]&.class&.name}"
end

# Job Watcher (Enqueue)
ActiveSupport::Notifications.subscribe("enqueue.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  job = payload[:job]

  capture_observation_entry({
    entry_type: "job",
    request_id: Current.request_id || "none",
    status: 100, # Enqueued status
    duration: 0.0,
    path: "#{job.class.name} (Enqueued)",
    payload: OBSERVATION_SCRUBBER.filter({
      arguments: job.arguments,
      queue: job.queue_name,
      executions: job.executions
    }),
    tags: [ "enqueued" ]
  })
end

# Job Watcher (Perform)
ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  job = payload[:job]

  capture_observation_entry({
    entry_type: "job",
    request_id: job.job_id,
    status: payload[:exception].present? ? 500 : 200,
    duration: event.duration,
    path: job.class.name,
    payload: OBSERVATION_SCRUBBER.filter({
      arguments: job.arguments,
      queue: job.queue_name,
      exception: payload[:exception],
      executions: job.executions
    }),
    tags: []
  })
end

# SQL Watcher
ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
  next if Thread.current[:observation_deck_silenced]

  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload

  # Guard: prevent recursive writes and ignore noisy queries
  sql = payload[:sql]
  next if sql.include?("observation_entries") || sql.include?("ar_internal_metadata") || sql.include?("schema_migrations")
  next if payload[:name] == "SCHEMA" || sql.include?("BEGIN") || sql.include?("COMMIT")

  # Only log slow SQL (> 100ms) or if we are in a request (all SQL for now to help dev)
  if event.duration > 100 || Current.respond_to?(:observation_buffer)
    capture_observation_entry({
      entry_type: "sql",
      request_id: Current.request_id || "none",
      status: payload[:exception].present? ? 500 : 200,
      duration: event.duration,
      path: payload[:name] || "SQL",
      payload: {
        sql: payload[:sql],
        binds: payload[:type_casted_binds]
      },
      tags: []
    })
  end
end

# Mail Watcher
ActiveSupport::Notifications.subscribe("deliver.action_mailer") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  mail_obj = payload[:mail]

  Rails.logger.info "[ObservationDeck] Capturing mail delivery: #{payload[:mailer]}"
  is_mail_object = mail_obj.respond_to?(:subject) && !mail_obj.is_a?(String)

  subject = is_mail_object ? mail_obj.subject : payload[:subject]
  to = is_mail_object ? mail_obj.to : payload[:to]
  from = is_mail_object ? mail_obj.from : payload[:from]

  # Extract body
  html_body = nil
  text_body = nil

  if is_mail_object
    html_body = mail_obj.html_part&.body&.to_s || (mail_obj.content_type =~ /html/ ? mail_obj.body&.to_s : nil)
    text_body = mail_obj.text_part&.body&.to_s || (mail_obj.content_type =~ /plain/ ? mail_obj.body&.to_s : nil)
  else
    # Fallback for string payloads: try to parse if it looks like raw mail
    begin
      parsed = Mail.new(mail_obj)
      html_body = parsed.html_part&.body&.to_s || (parsed.content_type =~ /html/ ? parsed.body&.to_s : nil)
      text_body = parsed.text_part&.body&.to_s || (parsed.content_type =~ /plain/ ? parsed.body&.to_s : nil)
    rescue
      html_body = mail_obj.to_s if mail_obj.to_s.include?("<html")
    end
  end

  capture_observation_entry({
    entry_type: "mail",
    request_id: Current.request_id || "none",
    status: payload[:exception].present? ? 500 : 200,
    duration: event.duration,
    path: payload[:mailer],
    payload: OBSERVATION_SCRUBBER.filter({
      subject: subject,
      to: to,
      from: from,
      html_body: html_body&.truncate(50000),
      text_body: text_body&.truncate(50000),
      exception: payload[:exception],
      exception_object: payload[:exception_object]&.message
    }),
    tags: payload[:exception].present? ? [ "error" ] : []
  })
end

# Outbound HTTP (Faraday / Channex / etc)
ActiveSupport::Notifications.subscribe("request.faraday") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload

  tags = [ payload[:url].include?("channex") ? "channex" : "api" ]

  # Parse body if possible for better viewing and ID extraction
  parsed_body = nil
  if payload[:body].present?
    begin
      parsed_body = JSON.parse(payload[:body])
    rescue JSON::ParserError
      parsed_body = payload[:body]
    end
  end

  # Extract Channex ID (Task ID, Revision ID, etc) for integration tests
  if payload[:url].include?("channex")
    # Body might be a raw JSON string (from background jobs) or already parsed (from request watcher)
    data_payload = parsed_body.is_a?(Hash) ? parsed_body : (JSON.parse(payload[:body]) rescue nil)
    
    if data_payload.is_a?(Hash)
      data = data_payload["data"]
      channex_id = if data.is_a?(Hash)
        data["id"]
      elsif data.is_a?(Array)
        data.first["id"] if data.first.is_a?(Hash)
      end
      tags << "channex_id:#{channex_id}" if channex_id.present?
    end
  end

  # Parse request body if possible
  parsed_request_body = nil
  if payload[:request_body].present?
    begin
      parsed_request_body = JSON.parse(payload[:request_body])
    rescue JSON::ParserError
      parsed_request_body = payload[:request_body]
    end
  end

  capture_observation_entry({
    entry_type: "api",
    request_id: Current.request_id || "none",
    status: payload[:status],
    duration: event.duration,
    path: "#{payload[:method].to_s.upcase} #{payload[:url]}",
    payload: OBSERVATION_SCRUBBER.filter({
      request_headers: payload[:request_headers],
      request_body: parsed_request_body,
      response_headers: payload[:response_headers],
      body: parsed_body
    }),
    tags: tags.uniq
  })
end

# Manual instrumentation helper for services not using notifications
def capture_api_call(provider, method, url, payload = {})
  start_time = Time.current
  result = yield
  duration = (Time.current - start_time) * 1000

  status, body = result

  tags = [ provider.downcase ]
  parsed_body = (JSON.parse(body) rescue nil) if body.is_a?(String)

  if provider.downcase == "channex" && (parsed_body || body).is_a?(Hash)
    data = (parsed_body || body)["data"]
    channex_id = if data.is_a?(Hash)
      data["id"]
    elsif data.is_a?(Array)
      data.first["id"] if data.first.is_a?(Hash)
    end
    tags << "channex_id:#{channex_id}" if channex_id.present?
  end

  capture_observation_entry({
    entry_type: "api",
    request_id: Current.request_id || "none",
    status: status,
    duration: duration,
    path: "#{method.to_s.upcase} [#{provider}] #{url}",
    payload: OBSERVATION_SCRUBBER.filter(payload.merge(response_body: parsed_body || body)),
    tags: tags.uniq
  })

  result
rescue => e
  duration = (Time.current - start_time) * 1000
  capture_observation_entry({
    entry_type: "api",
    request_id: Current.request_id || "none",
    status: 500,
    duration: duration,
    path: "#{method.to_s.upcase} [#{provider}] #{url}",
    payload: { error: e.message, backtrace: e.backtrace.first(5) },
    tags: [ provider.downcase, "error" ]
  })
  raise e
end
