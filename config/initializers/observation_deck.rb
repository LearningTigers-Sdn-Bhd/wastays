# Observation Deck Instrumentation Initializer

# Prevent crashing during migrations or test setup when table doesn't exist
if ActiveRecord::Base.connection.table_exists?("observation_entries")
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload

    # Filter sensitive params
    params = payload[:params].except("controller", "action")
    filtered_params = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)

    ObservationEntry.create!(
      entry_type: "request",
      request_id: payload[:request_id],
      status: payload[:status],
      duration: event.duration,
      path: "#{payload[:method]} #{payload[:path]}",
      payload: {
        params: filtered_params,
        view_runtime: payload[:view_runtime],
        db_runtime: payload[:db_runtime]
      }
    )
  end

  ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload
    job = payload[:job]

    ObservationEntry.create!(
      entry_type: "job",
      request_id: job.job_id, # Use job_id as request_id for tracking
      status: payload[:exception].present? ? 500 : 200,
      duration: event.duration,
      path: job.class.name,
      payload: {
        arguments: job.arguments,
        queue: job.queue_name,
        exception: payload[:exception]
      }
    )
  end

  ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    next if Thread.current[:observation_deck_silenced]

    event = ActiveSupport::Notifications::Event.new(*args)
    payload = event.payload

    # Constraint: Ignore queries on observation_entries to prevent infinite loops
    # Also ignore SCHEMA queries and transaction starts
    next if payload[:sql].include?("observation_entries")
    next if payload[:name] == "SCHEMA" || payload[:sql].include?("BEGIN") || payload[:sql].include?("COMMIT")

    begin
      Thread.current[:observation_deck_silenced] = true
      ObservationEntry.create!(
        entry_type: "sql",
        request_id: Current.request_id || "none",
        status: payload[:exception].present? ? 500 : 200,
        duration: event.duration,
        path: payload[:name] || "SQL",
        payload: {
          sql: payload[:sql],
          binds: payload[:type_casted_binds]
        }
      )
    ensure
      Thread.current[:observation_deck_silenced] = false
    end
  end
end
