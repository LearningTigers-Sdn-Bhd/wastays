# frozen_string_literal: true

module Notifications
  # Drives Notifications::AgentPaymentReminderScheduler on a schedule.
  #
  # Hourly, not by the minute: the offsets are whole hours and the scheduler
  # sends on the first run inside a window, so a finer schedule would only move
  # a reminder a few minutes earlier while asking the same question sixty times
  # as often. A missed run catches up on the next one, because nothing is queued
  # ahead -- what is due is decided when the job runs.
  class AgentPaymentRemindersJob < ApplicationJob
    queue_as :default

    def perform
      result = AgentPaymentReminderScheduler.call

      return if result.sent.empty?

      Rails.logger.info(
        "[agent_payment_reminder] sent #{result.sent.size}, superseded #{result.skipped.size}"
      )
    end
  end
end
