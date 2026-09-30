# frozen_string_literal: true

module HotelKnowledges
  class RecoverStaleIndexingJob < ApplicationJob
    queue_as :ai_concierge

    def perform
      RecoverStaleIndexing.new.call
    end
  end
end
