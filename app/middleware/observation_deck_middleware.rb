class ObservationDeckMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Initialize the buffer for this request
    Current.observation_buffer = []

    status, headers, response = @app.call(env)

    # Flush the buffer after the request is finished
    flush_buffer if Current.observation_buffer.present?

    [ status, headers, response ]

  ensure
    # Safety: always clear to prevent memory leaks in threads
    Current.observation_buffer = nil
  end

  private

  def flush_buffer
    # Use insert_all for high performance (ignores callbacks/validations)
    # Ensure created_at and updated_at are set manually since insert_all skips them
    now = Time.current
    entries = Current.observation_buffer.map do |entry|
      entry.merge(
        id: SecureRandom.uuid,
        created_at: now,
        updated_at: now,
        payload: entry[:payload].to_json,
        tags: entry[:tags].to_json
      )
    end

    # Run in a separate thread or just ensure it doesn't block the client?
    # Rack middleware call is after response is returned from app,
    # but still blocking the server thread.
    # For dev/small-scale, this is fine.
    # For large scale, we would use a background job or a dedicated thread.
    ObservationEntry.insert_all(entries)
  end
end
