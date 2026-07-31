# frozen_string_literal: true

module HotelPortal
  module Requests
    # Moving one request along.
    #
    # Three tables spell their statuses differently -- a complaint is resolved
    # where housekeeping is completed, and a checkout answers to a workflow
    # vocabulary of its own -- so this translates what was asked for into what
    # the record can be told, writes it, and then lets the rooms it covers and
    # the outside world know.
    class StatusUpdater
      attr_reader :hotel, :kind, :request_id, :status, :request

      def initialize(hotel:, kind:, request_id:, status:, trigger_webhook: true)
        @hotel = hotel
        @kind = kind.to_s
        @request_id = request_id
        @status = status.to_s
        @trigger_webhook = trigger_webhook
      end

      def call
        @request = find_request
        target_status = normalize_status
        previous_status = @request.status

        return false unless write(@request, target_status)

        RoomStatusSync.call(request: @request, kind: kind, status: target_status)
        if @trigger_webhook
          CompletionWebhook.broadcast(request: @request, kind: kind, from: previous_status, to: target_status)
        end

        @request
      end

      private

      def find_request
        Finder.new(hotel: hotel, kind: kind, request_id: request_id).call
      end

      # What the caller asked for, in the words the record answers to.
      def normalize_status
        return "resolved" if kind == "complaint" && status == "completed"
        return "completed" if kind == "housekeeping" && status == "completed"
        return status if kind == "checkout" && status.in?(%w[new assigned in_progress completed no_task cancelled])
        return "new" if kind == "checkout" && status == "pending"
        return "assigned" if kind == "checkout" && status == "acknowledged"

        status
      end

      def write(record, target_status)
        case kind
        when "housekeeping" then write_housekeeping(record, target_status)
        when "complaint" then write_complaint(record, target_status)
        when "checkout" then write_checkout(record, target_status)
        else false
        end
      end

      def write_housekeeping(record, target_status)
        return false unless HousekeepingRequest::STATUSES.include?(target_status)

        record.update(
          status: target_status,
          completed_at: finished_at(record, target_status == "completed"),
          metadata: released_metadata(record, target_status.in?(%w[new no_task]), record_history: true)
        )
      end

      def write_complaint(record, target_status)
        return false unless ComplaintRequest::STATUSES.include?(target_status)

        record.update(status: target_status, completed_at: finished_at(record, target_status == "resolved"))
      end

      def write_checkout(record, target_status)
        return false unless CheckOutRequest::STATUSES.include?(target_status)

        # Releasing a checkout drops who held it without noting it in the
        # history, which releasing housekeeping does. Preserved as it was rather
        # than levelled up inside a refactor; worth settling on purpose.
        metadata = released_metadata(record, @status == "no_task", record_history: false)
        metadata["workflow_status"] = @status

        record.update(
          status: target_status,
          metadata: metadata,
          completed_at: finished_at(record, target_status == "completed"),
          acknowledged_at: acknowledged_at(record, target_status)
        )
      end

      # Set when the work finishes, cleared when it is moved back, and never
      # moved once set.
      def finished_at(record, finished)
        finished ? (record.completed_at || Time.current) : nil
      end

      # Work handed back to nobody is work nobody holds, and the board says so.
      def released_metadata(record, released, record_history:)
        metadata = record.metadata.to_h
        return metadata unless released

        if record_history && metadata["assigned_to"].present?
          history = Array(metadata["assignment_history"])
          history << {
            "assigned_to_name" => "Unassigned",
            "assigned_by_name" => "System",
            "timestamp" => Time.current.iso8601
          }
          metadata["assignment_history"] = history
        end

        metadata.delete("assigned_to")
        metadata.delete("assigned_to_name")
        metadata
      end

      # A checkout records when somebody took it on, and keeps that through
      # finishing so the board can still say who did the work.
      def acknowledged_at(record, target_status)
        case target_status
        when "assigned", "in_progress" then record.acknowledged_at || Time.current
        when "completed" then record.acknowledged_at
        end
      end
    end
  end
end
