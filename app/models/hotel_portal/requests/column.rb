# frozen_string_literal: true

module HotelPortal
  module Requests
    # A lane on the board: what it is called, what it accepts, and what putting a
    # request in it means.
    #
    # These three used to be written apart -- the key in RequestsBoard::COLUMNS,
    # the label and colour in the presenter, and what a drop meant in the Stimulus
    # controller, which spelled a transition differently from the button beside
    # it. Adding one lane meant six edits and the chance to disagree with yourself
    # in any of them. A lane is one object now, and the board, the presenter, the
    # view and the drop all read the same one.
    #
    # What a lane is drawn from stays with the board: sources need the hotel, the
    # filters and the window, and a value object has no business holding a
    # relation.
    class Column
      # What a drop resolves to. A status is one the record answers to; an action
      # is something else the request has to be put through first.
      Transition = Struct.new(:status, :action, keyword_init: true) do
        def archive? = action == :archive
      end

      attr_reader :key, :label, :accent_class, :request_label, :count_badge_class

      def self.all
        @all ||= [
          new(key: :housekeeping, label: "Housekeeping", accent_class: "border-t-blue-500",
              request_label: "active request", count_badge_class: "bg-muted text-muted-foreground",
              reorderable: true, accepts: { "housekeeping" => "pending" }),
          new(key: :complaint, label: "Complaints", accent_class: "border-t-rose-500",
              request_label: "active request", count_badge_class: "bg-muted text-muted-foreground",
              reorderable: true, accepts: { "complaint" => "pending" }),
          new(key: :completed, label: "Recently Completed", accent_class: "border-t-green-500",
              request_label: "completed request", count_badge_class: "bg-muted text-muted-foreground",
              reorderable: true,
              # A complaint is resolved where housekeeping is completed.
              accepts: { "housekeeping" => "completed", "complaint" => "resolved", "checkout" => "completed" }),
          # A checkout request is raised by a guest checking out, not by staff
          # moving a card, so there is nothing a drop here could mean that would
          # not be inventing a record. Read-only on purpose.
          new(key: :checkout, label: "Checkout Requests", accent_class: "border-t-amber-500",
              request_label: "pending request", count_badge_class: "bg-amber-100 text-amber-700",
              reorderable: false, accepts: {}),
          new(key: :archived, label: "Archived", accent_class: "border-t-slate-400",
              request_label: "archived request", count_badge_class: "bg-muted text-muted-foreground",
              reorderable: false, archives: true)
        ].freeze
      end

      def self.keys = @keys ||= all.map(&:key).freeze

      def self.find(key)
        all.find { |column| column.key == key.to_s.to_sym }
      end

      def self.exists?(key) = find(key).present?

      # The lane a request belongs in as it stands, which is where restoring one
      # from the archive puts it back.
      def self.for_record(kind:, status:, archived:)
        return find(:archived) if archived
        return find(:completed) if FINISHED_STATUSES.include?(status.to_s)

        find(kind.to_s == "checkout" ? :checkout : kind.to_s.to_sym) || find(:housekeeping)
      end

      FINISHED_STATUSES = %w[completed resolved].freeze

      def initialize(key:, label:, accent_class:, request_label:, count_badge_class:,
                     reorderable:, accepts: {}, archives: false)
        @key = key
        @label = label
        @accent_class = accent_class
        @request_label = request_label
        @count_badge_class = count_badge_class
        @reorderable = reorderable
        @accepts = accepts.freeze
        @archives = archives
        freeze
      end

      def reorderable? = @reorderable
      def archives? = @archives
      def droppable? = @archives || @accepts.any?

      def accepts?(kind) = transition_for(kind).present?

      # What it means to put a request of this kind here, or nil if it cannot go.
      # The archive takes anything, because anything can be put away.
      def transition_for(kind)
        return Transition.new(action: :archive) if archives?

        status = @accepts[kind.to_s]
        Transition.new(status: status) if status
      end

      def to_param = key.to_s
    end
  end
end
