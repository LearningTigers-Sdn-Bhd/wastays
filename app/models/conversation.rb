# frozen_string_literal: true

# One continuous exchange with one person on one channel.
#
# `mode` is the important column: it decides who is allowed to answer. While it
# reads "bot" the AI replies; the moment a staff member takes the thread it
# flips to "human" and the AI must stay silent, or the guest gets two answers
# to one question. Nothing here depends on the AI existing -- a hotel with it
# switched off has a plain message desk staffed by people.
class Conversation < ApplicationRecord
  include HotelScopable

  CHANNELS = %w[web whatsapp api].freeze

  # Where a staff reply can arrive at all. The web chat is a page the hotel
  # owns, so the guest's browser is already listening. WhatsApp is somebody
  # else's network: the app has no connection to it and reaches it through a
  # relay, so a WhatsApp thread is only replyable when a relay is actually
  # connected -- see `reply_blocker`. Anywhere else a reply box would be a
  # promise the app cannot keep, so it is not offered.
  REPLYABLE_CHANNELS = %w[web whatsapp].freeze

  # Why a reply cannot be sent, in the words staff are shown.
  #
  # One place rather than a boolean and a guess, because the reply box and the
  # refusal from `Concierge::PostStaffReply` have to give the same reason -- a
  # box that says one thing and an error that says another is worse than
  # either.
  REPLY_BLOCKERS = {
    unsupported_channel: "Replies to this channel cannot be delivered yet.",
    no_guest_number: "This guest has no phone number on file, so a WhatsApp reply has nowhere to go.",
    no_relay: "No WhatsApp relay is connected for this hotel, so a reply would not reach the guest."
  }.freeze

  # The one line under the hotel's name in the chat bar. Deliberately about who
  # answers rather than a status light -- "online" would be a promise the page
  # cannot keep at 3am.
  # What the bot answers in when nobody has established anything else.
  DEFAULT_LANGUAGE = "en"

  BOT_STATUS = "Ask about your stay, any time"
  FRONT_DESK_STATUS = "Our front desk replies here"
  HUMAN_REQUESTED_STATUS = "A team member has been asked to join"
  MODES = %w[bot human].freeze
  STATUSES = %w[open closed].freeze

  belongs_to :prospect
  belongs_to :assigned_user, class_name: "User", optional: true

  has_many :messages,
           -> { chronological },
           class_name: "ProspectMessage",
           inverse_of: :conversation,
           dependent: :destroy

  after_update_commit :broadcast_status_to_guest, if: :saved_change_to_guest_status_facts?
  after_update_commit :broadcast_to_inbox, if: :saved_change_to_inbox_facts?

  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :mode, presence: true, inclusion: { in: MODES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  # Threads a person is expected to look at: the ones staff already hold, and
  # the ones a guest has asked them to. Defined here rather than in the inbox
  # query, because the guest's page and the tab counts have to agree with it.
  scope :awaiting_staff, -> { open.where(mode: "human").or(open.where.not(human_requested_at: nil)) }
  scope :recent_first, -> { order(last_message_at: :desc, created_at: :desc) }

  def replies_reach_guest? = reply_blocker.nil?
  def reply_blocker_message = REPLY_BLOCKERS[reply_blocker]

  # nil when a reply would reach the guest, otherwise which thing is missing.
  #
  # Checked per thread rather than per channel because both answers are facts
  # about this conversation, not about WhatsApp: a hotel with no relay
  # connected cannot deliver anything, and a prospect who has only ever used
  # the web chat has no number to deliver to.
  def reply_blocker
    return nil if channel == "web"
    return :unsupported_channel unless REPLYABLE_CHANNELS.include?(channel)
    return :no_guest_number if prospect.phone_number.blank?
    return :no_relay unless staff_replies_relayed?

    nil
  end

  def staff_replies_relayed?
    WebhookEndpoint.listening_for(Concierge::DeliverStaffReply::EVENT, hotel_id: hotel_id).exists?
  end

  # What the guest is told about who is answering them.
  #
  # It lives on the model because two places have to say the same thing: the
  # chat page when it loads, and the live replacement pushed the moment mode
  # changes under a guest who is already looking at it.
  #
  # Always a sentence, never nothing: it holds a fixed line in the bar, and a
  # bar whose second line comes and goes moves the hotel's name up and down
  # while the guest reads.
  def guest_status
    return { text: "#{assigned_user&.name.presence || "Our front desk"} is answering you now", tone: :accent } if human?
    return { text: HUMAN_REQUESTED_STATUS, tone: :accent } if human_requested?

    self.class.guest_status_for(hotel)
  end

  # The same answer for a visitor who has not written yet, and so has no thread
  # to ask. Only the hotel is known at that point.
  def self.guest_status_for(hotel)
    { text: hotel.ai_concierge_ready? ? BOT_STATUS : FRONT_DESK_STATUS }
  end

  # The language the bot answers this thread in.
  #
  # Most of a booking is answered with a number or a yes -- "1", "no 2",
  # "yes" -- and none of those are written in any language. So the thread remembers what the guest last wrote a sentence in,
  # and a message carrying no signal of its own keeps it rather than snapping
  # everyone back to English halfway down the ladder.
  def reply_language = language.presence || DEFAULT_LANGUAGE
  def translated? = language.present? && language != DEFAULT_LANGUAGE

  # Only a message that actually established a language writes one. Nothing is
  # recorded for a bare option number, which is the point of storing it at all.
  def record_language!(value)
    return self if value.blank? || value == language

    update!(language: value)
    self
  end

  def bot? = mode == "bot"
  def human? = mode == "human"
  def open? = status == "open"
  def human_requested? = human_requested_at.present?

  # The guest asks; the assistant carries on answering until somebody actually
  # arrives. Asked twice is still asked once -- the first ask is the one that
  # tells staff how long they have been waiting.
  def request_human!(at: Time.current)
    return self if human? || human_requested?

    update!(human_requested_at: at)
    self
  end

  # Handing over is one move, not two: the bot stops answering and the thread
  # gains an owner at the same moment.
  # The request is cleared as the person arrives: it is a call for someone, and
  # it stops meaning anything the moment someone answers it.
  def hand_to_human!(user: nil)
    update!(mode: "human", assigned_user: user, human_requested_at: nil)
  end

  def return_to_bot!
    update!(mode: "bot", assigned_user: nil)
  end

  def close!(at: Time.current)
    update!(status: "closed", closed_at: at)
  end

  # Reopening drops the closing timestamp rather than keeping it as history:
  # the partial unique index only tolerates one open thread per person per
  # channel, and a stale closed_at on an open row reads as a contradiction.
  def reopen!
    update!(status: "open", closed_at: nil)
  end

  def unread_count = messages.unread.count

  # The inbox as everyone else has it open.
  #
  # Two separate pushes because they answer to different things. The row is
  # about this thread and only lands where the reader already has it; the counts
  # are facts about the whole hotel, and go stale for a reader whose screen this
  # thread never appears on.
  #
  # The row is *updated*, not replaced: which thread a reader has open is the
  # one thing on this screen that is true for them and nobody else, and it lives
  # on the row itself. Nor is the list re-sorted -- a row that jumps under the
  # cursor of somebody about to click it is worse than a row briefly out of
  # order, and any navigation puts it back.
  def broadcast_to_inbox
    broadcast_update_to(
      [ hotel, :conversations ],
      target: HotelPortal::Inbox::ListItem.dom_id_for(self),
      renderable: HotelPortal::Inbox::ListItemBody.new(conversation: self, hotel: hotel)
    )
    broadcast_counts_to_inbox
  end

  def broadcast_counts_to_inbox
    counts = HotelPortal::ConversationsQuery.new(hotel: hotel).counts

    counts.each do |key, value|
      broadcast_update_to(
        [ hotel, :conversations ],
        target: "conversation-count-#{key}",
        html: value.to_s
      )
    end
  end

  # A thread nobody has seen before, arriving at the top of the list.
  #
  # Sent when the guest's first message lands rather than when the row is
  # created, because until then there is nothing to show and no way to tell
  # which tabs it belongs on. A reader filtered to a tab it does not belong on
  # is not subscribed to that stream, so it does not appear there.
  def broadcast_arrival_to_inbox
    inbox_tabs.each do |tab|
      broadcast_prepend_to(
        [ hotel, :conversations, tab ],
        target: "conversation-rows",
        renderable: HotelPortal::Inbox::ListItem.new(conversation: self, hotel: hotel)
      )
    end
  end

  private

  # Which tabs of the inbox this thread belongs on right now.
  def inbox_tabs
    return [ "closed" ] unless open?

    tabs = [ "all" ]
    tabs << "unread" if messages.unread.from_guest.exists?
    tabs << "awaiting_staff" if human? || human_requested?
    tabs
  end

  # What the list actually shows about a thread: who is holding it, and whether
  # it is still open. A change to anything else is not worth a push.
  def saved_change_to_inbox_facts?
    saved_change_to_mode? || saved_change_to_status? || saved_change_to_assigned_user_id? ||
      saved_change_to_human_requested_at?
  end

  # Everything the line under the hotel's name is built from.
  def saved_change_to_guest_status_facts?
    saved_change_to_mode? || saved_change_to_assigned_user_id? || saved_change_to_human_requested_at?
  end

  # The guest's page is already open when staff take the thread; the line under
  # the hotel's name would otherwise still name the bot until they reload.
  def broadcast_status_to_guest
    broadcast_replace_to(
      [ self, :guest ],
      target: PublicUI::Chat::Status::DEFAULT_ID,
      renderable: PublicUI::Chat::Status.new(**guest_status)
    )
  end
end
