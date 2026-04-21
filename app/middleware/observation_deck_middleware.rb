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
    count = Current.observation_buffer.size
    now = Time.current

    # All objects must have the same keys for insert_all
    entries = Current.observation_buffer.map do |entry|
      {
        id: SecureRandom.uuid,
        entry_type: entry[:entry_type],
        request_id: entry[:request_id] || "none",
        status: entry[:status],
        duration: entry[:duration] || 0.0,
        path: entry[:path],
        payload: entry[:payload] || {},
        tags: entry[:tags] || [],
        created_at: now,
        updated_at: now
      }
    end

    ObservationEntry.insert_all(entries)
  rescue => e
    Rails.logger.error "[ObservationDeck] Flush failed: #{e.message}"
  end
end
