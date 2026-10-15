# frozen_string_literal: true

# Feeds the admin Mail Log. Each delivered or failed email becomes one MailEvent.
ActiveSupport::Notifications.subscribe("deliver.action_mailer") do |event|
  MailEvents::Record.call(payload: event.payload)
end
