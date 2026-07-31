# frozen_string_literal: true

module HotelPortal
  module Requests
    # Putting a request in a lane.
    #
    # A card dragged across the board and a button pressed on that card are the
    # same operation asked for two ways, so they arrive here rather than at two
    # endpoints that can drift apart -- which is how dragging came to write
    # "pending" where the button beside it wrote "new".
    #
    # What a lane means is the lane's own business (Column), and how a record is
    # told stays with the updaters. This decides only whether the move is allowed
    # and what has to happen for it: a request leaving the archive is restored
    # before it is given a status, because an archived request in an open lane is
    # not a state the board has a way of showing.
    class Move
      Result = Struct.new(:request, :from_column, :to_column, :error, keyword_init: true) do
        def ok? = error.nil?
      end

      attr_reader :hotel, :kind, :display_kind, :request_id, :to

      # `kind` is the table the request is in and `display_kind` is the lane it
      # was shown as -- the same for everything except a checkout's room
      # cleaning, which is a housekeeping row wearing a checkout badge. What a
      # lane accepts is answered for what the operator saw; the record is
      # reached by what it is.
      def initialize(hotel:, kind:, request_id:, to:, display_kind: nil)
        @hotel = hotel
        @kind = kind.to_s
        @display_kind = display_kind.presence&.to_s || @kind
        @request_id = request_id
        @to = to
      end

      def call
        return failure("Unknown column.") if target.nil?

        request = Finder.new(hotel: hotel, kind: kind, request_id: request_id).call
        from = column_for(request)

        return failure("That request is already there.") if from.key == target.key

        transition = target.transition_for(display_kind)
        return failure("A #{display_kind} request cannot go there.") if transition.nil?

        apply(request, from, transition)
      end

      private

      def apply(request, from, transition)
        if transition.archive?
          return failure("Could not archive the request.") unless archive_updater.archive

          return success(request.reload, from)
        end

        # Leaving the archive is a restore first: the status it is being given
        # belongs to a request the board can show.
        if from.archives? && !archive_updater.unarchive
          return failure("Could not restore the request.")
        end

        updated = StatusUpdater.new(
          hotel: hotel, kind: kind, request_id: request_id, status: transition.status
        ).call

        return failure("Could not update the request.") unless updated

        success(updated, from)
      end

      def column_for(request)
        Column.for_record(kind: display_kind, status: request.status, archived: archived?(request))
      end

      # A checkout keeps no archived_at column; a note in its metadata is what
      # putting one away amounts to.
      def archived?(request)
        return request.metadata.to_h["archived_at"].present? if kind == "checkout"

        request.archived_at.present?
      end

      def archive_updater
        @archive_updater ||= ArchiveUpdater.new(hotel: hotel, kind: kind, request_id: request_id)
      end

      def target = @target ||= Column.find(to)

      def success(request, from) = Result.new(request: request, from_column: from, to_column: target)
      def failure(message) = Result.new(error: message, to_column: target)
    end
  end
end
