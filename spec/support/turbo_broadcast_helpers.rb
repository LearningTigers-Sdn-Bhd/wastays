# frozen_string_literal: true

# Reads what a model actually pushed down a Turbo Stream.
#
# turbo-rails ships its own helper, but it is built on Minitest assertions that
# are not available here. This does the one thing the specs need: hand back the
# payloads that landed on a stream, in the order they were sent.
module TurboBroadcastHelpers
  include Turbo::Streams::StreamName

  # Decoded, because the adapter stores each payload JSON-encoded and a spec
  # asserting on escaped quotes is a spec about the transport.
  def turbo_broadcasts_to(*streamables)
    ActionCable.server.pubsub
               .broadcasts(stream_name_from(streamables))
               .map { |payload| ActiveSupport::JSON.decode(payload) }
  end
end

RSpec.configure do |config|
  config.include TurboBroadcastHelpers

  # The pubsub adapter is a singleton, so one example's broadcasts would
  # otherwise be counted by the next.
  config.before do
    pubsub = ActionCable.server.pubsub
    pubsub.clear if pubsub.respond_to?(:clear)
  end
end
