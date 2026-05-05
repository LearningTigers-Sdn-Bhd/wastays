# frozen_string_literal: true

class CleanupRoomLocksJob < ApplicationJob
  queue_as :default

  def perform
    RoomLock.cleanup_expired!
  end
end
