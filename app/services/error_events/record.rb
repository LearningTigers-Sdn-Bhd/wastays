# frozen_string_literal: true

module ErrorEvents
  # Writes one ErrorEvent for each error that Rails.error reports.
  # It never raises and never reports its own failure, so it cannot cause a loop.
  class Record
    # Missing pages and bad requests are not faults of the app.
    IGNORED = %w[
      ActionController::RoutingError
      ActionController::UnknownFormat
      ActionController::InvalidAuthenticityToken
      ActionController::BadRequest
      ActionController::ParameterMissing
      ActiveRecord::RecordNotFound
    ].freeze
    MAX_CONTEXT_BYTES = 10_000

    def self.call(...) = new(...).call

    def initialize(error:, handled:, severity:, context:, source: nil)
      @error = error
      @handled = handled
      @severity = severity
      @context = context
      @source = source
    end

    def call
      return if IGNORED.include?(@error.class.name)

      ErrorEvent.create!(
        error_class: @error.class.name,
        message: @error.message.to_s.truncate(2_000),
        backtrace: backtrace,
        severity: @severity.to_s,
        handled: @handled ? true : false,
        source: @source.to_s.presence,
        context: context,
        occurred_at: Time.current
      )
    rescue StandardError, SystemStackError => e
      Rails.logger.error("[ErrorEvents::Record] #{e.class}: #{e.message}")
      nil
    end

    private

    def backtrace
      lines = @error.backtrace || []
      (Rails.backtrace_cleaner.clean(lines).presence || lines).first(20).join("\n").presence
    end

    # Keep plain values only. Rails can put objects such as the request in the context.
    # Secrets are filtered the same way as in the logs. A large context is dropped.
    def context
      plain = plain_value(@context.to_h)
      filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(plain)
      filtered.to_json.bytesize > MAX_CONTEXT_BYTES ? { "truncated" => true } : filtered
    end

    def plain_value(value, depth = 0)
      case value
      when String, Numeric, true, false, nil then value
      when Symbol then value.to_s
      when Hash then depth < 3 ? value.to_h { |key, item| [ key.to_s, plain_value(item, depth + 1) ] } : value.class.name
      when Array then depth < 3 ? value.first(20).map { |item| plain_value(item, depth + 1) } : value.class.name
      else value.class.name
      end
    end
  end
end
