# frozen_string_literal: true

# Registers :million_send as an ActionMailer delivery method (see lib/million_send_delivery.rb).
# Selected in production/demo when credentials million_send.api_key (or MILLIONSEND_API_KEY) is set;
# the env files put the key in config.x.million_send_api_key.
ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :million_send, MillionSendDelivery, api_key: Rails.application.config.x.million_send_api_key
end
