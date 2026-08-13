# frozen_string_literal: true

module ChannelManagers
  SyncResult = Data.define(:status, :message, :warnings, :task_ids) do
    STATUSES = %i[full_success partial_success availability_only unsupported_pricing failure].freeze
    SUCCESS_STATUSES = %i[full_success partial_success availability_only].freeze

    def self.build(status, message, warnings: [], task_ids: {})
      raise ArgumentError, "Unknown channel sync status: #{status}" unless status.in?(STATUSES)

      new(status: status, message: message, warnings: Array(warnings), task_ids: task_ids.compact)
    end

    def success? = status.in?(SUCCESS_STATUSES)
    def unsupported? = status == :unsupported_pricing
    def failure? = status == :failure
  end
end
