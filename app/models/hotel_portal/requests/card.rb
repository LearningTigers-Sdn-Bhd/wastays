# frozen_string_literal: true

module HotelPortal
  module Requests
    # One request as the board and the archive show it.
    #
    # Three tables with three vocabularies are flattened into one thing a card
    # can be drawn from. This was a fifteen-key hash built by five methods across
    # two services and read by string key in two views and a presenter -- so a key
    # spelled wrong read as nil and the card simply came out blank.
    #
    # It answers to [] as well as to its readers, because the cursor sorts on
    # rows without caring what built them.
    Card = Struct.new(
      :kind, :record_kind, :request_id, :booking_id, :booking_token, :guest_name, :title,
      :room_number, :status, :requested_at, :completed_at, :archived_at, :source,
      :internal_notes, :archive_url, :update_url, :complete_url, :booking_url,
      :sort_at, :sort_source,
      keyword_init: true
    ) do
      # What the card says it is, and what it actually is, are not always the
      # same: a checkout's room cleaning is a housekeeping row shown as a
      # checkout. `kind` is the badge; `record_kind` is the table. Anything that
      # has to reach the record -- a URL, a lookup, an id -- wants this one, and
      # sending the badge instead looks the id up in the wrong table.
      def record_kind = self[:record_kind].presence || kind

      # Stable across every render, so a stream can name one card on a board it
      # did not draw. Ids repeat across the three tables, hence the kind.
      def dom_id = "request_#{record_kind}_#{request_id}"

      def internal_notes_list = Array(internal_notes)

      def finished? = status.to_s.in?(Column::FINISHED_STATUSES)
    end
  end
end
