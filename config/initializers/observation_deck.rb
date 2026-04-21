# Observation Deck Instrumentation Initializer

# Helper to deeply scrub sensitive data
OBSERVATION_SCRUBBER = ActiveSupport::ParameterFilter.new(
  Rails.application.config.filter_parameters + [ :credit_card, :cvv, :passport, :ssn ]
)

# Helper to store entries (buffered for requests, immediate for jobs)
def capture_observation_entry(entry_data)
  if Current.respond_to?(:observation_buffer) && Current.observation_buffer.is_a?(Array)
    Current.observation_buffer << entry_data
  else
    # Outside of a request (e.g., background job), save immediately
    ObservationEntry.create!(entry_data) rescue nil
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
      request_id: payload[:request_id],
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

# Job Watcher
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
  mail = payload[:mail]

  next unless mail.respond_to?(:subject)

  # Truncate body to 50k chars
  html_body = mail.respond_to?(:html_part) ? mail.html_part&.body&.to_s : nil
  html_body ||= mail.body.to_s if mail.respond_to?(:body)
  
  text_body = mail.respond_to?(:text_part) ? mail.text_part&.body&.to_s : nil

  capture_observation_entry({
    entry_type: "mail",
    request_id: Current.request_id || "none",
    status: 200,
    duration: event.duration,
    path: payload[:mailer],
    payload: OBSERVATION_SCRUBBER.filter({
      subject: payload[:mail].subject,
      to: payload[:mail].to,
      from: payload[:mail].from,
      html_body: html_body&.truncate(50000),
      text_body: text_body&.truncate(50000)
    }),
    tags: []
  })
end

# Outbound HTTP (Faraday)
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
    tags: []
  })
end
