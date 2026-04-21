class ObservationDeckMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    Current.observation_buffer = []

    status, headers, response = @app.call(env)

    if Current.observation_buffer.present?
      Rails.logger.info "[ObservationDeck] Found #{Current.observation_buffer.size} entries to flush."
      flush_buffer 
    end

    [ status, headers, response ]
  ensure
    Current.observation_buffer = nil
  end

  private

  def flush_buffer
    now = Time.current
    entries = Current.observation_buffer.map do |entry|
      {
        id: SecureRandom.uuid,
        entry_type: entry[:entry_type].to_s,
        request_id: entry[:request_id].to_s || "none",
        status: entry[:status],
        duration: entry[:duration].to_f || 0.0,
        path: entry[:path].to_s,
        payload: entry[:payload] || {},
        tags: entry[:tags] || [],
        created_at: now,
        updated_at: now
      }
    end

    result = ObservationEntry.insert_all(entries)
    Rails.logger.info "[ObservationDeck] Successfully inserted #{result.size} entries."
  rescue => e
    Rails.logger.error "[ObservationDeck] Flush failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
  end

end
