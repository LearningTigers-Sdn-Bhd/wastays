# frozen_string_literal: true

# Feeds the admin Activity Log error tab. Each reported error becomes one ErrorEvent.
# The subscriber calls the service by name, so code reloading in development still works.
Rails.error.subscribe(
  Object.new.tap do |subscriber|
    subscriber.define_singleton_method(:report) do |error, handled:, severity:, context:, source: nil|
      ErrorEvents::Record.call(error: error, handled: handled, severity: severity, context: context, source: source)
    end
  end
)
