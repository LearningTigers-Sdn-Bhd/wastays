# frozen_string_literal: true

module Concierge
  class CloseStaleConversationsJob < ApplicationJob
    queue_as :default

    def perform
      Concierge::CloseStaleConversations.new.call
    end
  end
end
