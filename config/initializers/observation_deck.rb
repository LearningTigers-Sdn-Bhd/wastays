# Observation Deck Instrumentation Initializer

# Prevent crashing during migrations or test setup when table doesn't exist
begin
  if ActiveRecord::Base.connected? && ActiveRecord::Base.connection.table_exists?("observation_entries")
    # Helper to capture tags (e.g., ["user:12", "booking:WA-99"])
    def capture_tags(payload)
    tags = []

    # Extract user context
    if Current.respond_to?(:user_id) && Current.user_id.present?
      tags << "user:#{Current.user_id}"
    end

    # Extract booking from params
    if payload[:params].present?
      booking_id = payload[:params]["booking_id"] || payload[:params]["id"] if payload[:params]["controller"]&.include?("bookings")
      tags << "booking:#{booking_id}" if booking_id.present?
    end

    tags.uniq
  end

  # Helper to deeply scrub sensitive data
  def scrub_payload(payload)
    scruuber = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters + [ :credit_card, :cvv, :passport, :ssn ])

    scruuber.filter(payload)
  end

  # Helper to store entries (buffered for requests, immediate for jobs)
  def capture_entry(entry_data)
    if Current.respond_to?(:observation_buffer) && Current.observation_buffer.is_a?(Array)
      Current.observation_buffer << entry_data
    else
      # Outside of a request (e.g., background job), save immediately
      ObservationEntry.create!(entry_data)
    end
  end

  # Request Watcher
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload
    status = payload[:status].to_i

    # Sampling Strategy:
    # 100% Errors (>= 400)
    # 100% Slow Requests (> 1000ms)
    # 10% Success (200)
    is_error = status >= 400
    is_slow = event.duration > 1000
    is_sampled = rand < 0.1

    if is_error || is_slow || is_sampled
      params = payload[:params].except("controller", "action")

      capture_entry({
        entry_type: "request",
        request_id: payload[:request_id],
        status: status,
        duration: event.duration,
        path: "#{payload[:method]} #{payload[:path]}",
        tags: capture_tags(payload),
        payload: scrub_payload({
          params: params,
          view_runtime: payload[:view_runtime],
          db_runtime: payload[:db_runtime],
          format: payload[:format],
          controller: payload[:controller],
          action: payload[:action]
        })
      })
    end
  end

  # Job Watcher
  ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload
    job = payload[:job]

    capture_entry({
      entry_type: "job",
      request_id: job.job_id,
      status: payload[:exception].present? ? 500 : 200,
      duration: event.duration,
      path: job.class.name,
      payload: scrub_payload({
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

    begin
      Thread.current[:observation_deck_silenced] = true

      # For SQL, we only log if it's slow or if we are in a sampled request
      # For now, let's log slow SQL (> 100ms) or if specifically enabled
      if event.duration > 100
        capture_entry({
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
    ensure
      Thread.current[:observation_deck_silenced] = false
    end
  end

  # Mail Watcher
  ActiveSupport::Notifications.subscribe("deliver.action_mailer") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload

    # Truncate body to 50k chars
    html_body = payload[:mail].html_part&.body&.to_s || payload[:mail].body&.to_s
    text_body = payload[:mail].text_part&.body&.to_s

    capture_entry({
      entry_type: "mail",
      request_id: Current.request_id || "none",
      status: 200,
      duration: event.duration,
      path: payload[:mailer],
      payload: scrub_payload({
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

    capture_entry({
      entry_type: "api",
      request_id: Current.request_id || "none",
      status: payload[:status],
      duration: event.duration,
      path: "#{payload[:method].to_s.upcase} #{payload[:url]}",
      payload: scrub_payload({
        request_headers: payload[:request_headers],
        response_headers: payload[:response_headers],
        body: payload[:body] # Be careful with body size
      }),
      tags: []
    })
  end
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, PG::Error
  # Database not ready or table doesn't exist yet (e.g. during migration)
end
