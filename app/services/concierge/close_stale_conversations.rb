# frozen_string_literal: true

module Concierge
  # Puts away threads nobody has said anything on for days.
  #
  # An enquiry is over long before anyone marks it so. Left alone, every thread
  # a guest ever opened stays in the inbox as if it were live, and each one
  # holds the person's single open slot on that channel -- so a guest coming
  # back in a month resumes a conversation about dates that have passed instead
  # of starting a new one.
  #
  # Deliberately not tied to WhatsApp's 24-hour reply window
  # (`Conversation::REPLY_WINDOW`), even though the two look alike. That one is
  # Meta's rule about *sending*; this one is a decision about what counts as a
  # single enquiry. Letting Meta's policy set the product's memory would also
  # mean splitting at exactly 24 hours, which shows staff two threads where the
  # guest, scrolling one continuous chat on their phone, sees one -- losing
  # yesterday's context exactly when it is needed.
  #
  # A sweep rather than a check on the next message, because the whole point is
  # that nothing arrives: a thread that goes quiet is never touched again, so
  # nothing would ever run the check.
  class CloseStaleConversations
    # Long enough that a guest who slept on it and answered the next evening is
    # still in the same conversation.
    STALE_AFTER = 3.days

    # How many to close in one run. The first run after this ships has every
    # thread ever abandoned waiting for it, and closing them all at once would
    # be one long transaction and a flood of pushes into every open inbox.
    # Hourly runs drain the backlog over a day or so instead.
    BATCH_LIMIT = 200

    # Said in the transcript rather than only in the log, for the same reason
    # `ClearConversation` says its piece: a staff member reading this later
    # should not have to guess why it stops mid-sentence.
    CLOSING_NOTE = "Closed automatically after three days with no reply."

    def initialize(now: Time.current, limit: BATCH_LIMIT)
      @now = now
      @limit = limit
    end

    # Returns how many threads were closed.
    def call
      stale = Conversation.inactive_since(now - STALE_AFTER)
                          .includes(:hotel, :prospect)
                          .oldest_activity_first
                          .limit(limit)
                          .to_a
      return 0 if stale.empty?

      stale.group_by(&:hotel).each { |hotel, conversations| close_all(hotel, conversations) }
      stale.size
    end

    private

    attr_reader :now, :limit

    # Per hotel, because the counts are per hotel: the rows go out as each
    # thread closes, and the tab counts go out once at the end.
    def close_all(hotel, conversations)
      Conversation.deferring_inbox_counts do
        conversations.each { |conversation| close(conversation) }
      end

      Conversation.broadcast_counts_to_inbox(hotel)
    end

    # One thread failing -- a validation the sweep cannot see, a hotel row that
    # went away underneath it -- must not take the rest of the batch with it.
    def close(conversation)
      announce(conversation)
      conversation.close!(at: now)
    rescue StandardError => e
      Rails.logger.error("Concierge::CloseStaleConversations failed on ##{conversation.id}: #{e.message}")
    end

    # Nothing to explain on a thread that never had a word in it, and writing
    # the note there would be the row's first message -- which announces its
    # arrival to the inbox a moment before it closes.
    def announce(conversation)
      return if conversation.messages.empty?

      conversation.messages.create!(
        prospect: conversation.prospect,
        direction: "system",
        sender_role: "system",
        body: CLOSING_NOTE
      )
    end
  end
end
