# Observation Deck Instrumentation Initializer

# Helper to deeply scrub sensitive data
OBSERVATION_SCRUBBER = ActiveSupport::ParameterFilter.new(
  Rails.application.config.filter_parameters + [ :credit_card, :cvv, :passport, :ssn ]
)

# Helper to store entries (buffered for requests, immediate for jobs)
def capture_observation_entry(entry_data)
  entry_data[:request_id] = entry_data[:request_id].presence || Current.request_id || "none"

  if Current.respond_to?(:observation_buffer) && Current.observation_buffer.is_a?(Array)
    Current.observation_buffer << entry_data
  else
    # Outside of a request (e.g., background job), save immediately
    begin
      ObservationEntry.create!(entry_data)
    rescue => e
      puts "[ObservationDeck] ERROR: #{e.message}"
      Rails.logger.error "[ObservationDeck] Failed to log entry: #{e.message}"
    end
  end
end

# Request Watcher
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  payload = event.payload
  status = payload[:status].to_i

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
    end

    capture_observation_entry({
      entry_type: "request",
      request_id: payload[:request_id].presence || Current.request_id || "none",
      status: status,
      duration: event.duration,
      path: "#{payload[:method]} #{payload[:path]}",
      tags: tags.uniq,
      payload: OBSERVATION_SCRUBBER.filter({
        params: payload[:params].except("controller", "action"),
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
  next if payload[:sql].include?("observation_entries")
  next if payload[:name] == "SCHEMA" || payload[:sql].include?("BEGIN") || payload[:sql].include?("COMMIT")

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

  capture_observation_entry({
    entry_type: "api",
    request_id: Current.request_id || "none",
    status: payload[:status],
    duration: event.duration,
    path: "#{payload[:method].to_s.upcase} #{payload[:url]}",
    payload: OBSERVATION_SCRUBBER.filter({
      request_headers: payload[:request_headers],
      response_headers: payload[:response_headers],
      body: payload[:body]
    }),
    tags: [ payload[:url].include?("channex") ? "channex" : "api" ]
  })
end

# Manual instrumentation helper for services not using notifications
def capture_api_call(provider, method, url, payload = {})
  start_time = Time.current
  result = yield
  duration = (Time.current - start_time) * 1000

  status, body = result

  capture_observation_entry({
    entry_type: "api",
    request_id: Current.request_id || "none",
    status: status,
    duration: duration,
    path: "#{method.to_s.upcase} [#{provider}] #{url}",
    payload: OBSERVATION_SCRUBBER.filter(payload.merge(response_body: body)),
    tags: [ provider.downcase ]
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
