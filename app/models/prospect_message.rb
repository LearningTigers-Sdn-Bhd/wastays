class ProspectMessage < ApplicationRecord
  DIRECTIONS = %w[inbound outbound system].freeze
  SENDER_ROLES = %w[guest bot staff system].freeze

  # Which way the message travelled, and who wrote it, are two different
  # questions. A bot answer and a staff answer are both "outbound"; only
  # sender_role separates them, which is what the inbox needs to render them
  # differently and what tells you whether a human has actually replied yet.
  DIRECTION_DEFAULT_SENDER_ROLES = {
    "inbound" => "guest",
    "outbound" => "bot",
    "system" => "system"
  }.freeze

  belongs_to :prospect
  belongs_to :conversation, optional: true
  belongs_to :sender_user, class_name: "User", optional: true
  has_many :hotel_knowledge_diagnostics, dependent: :nullify

  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  validates :sender_role, presence: true, inclusion: { in: SENDER_ROLES }
  validates :body, presence: true

  before_validation :set_sent_at, on: :create
  before_validation :derive_sender_role, on: :create
  after_create :touch_conversation
  after_create_commit :broadcast_to_both_sides

  scope :chronological, -> { order(sent_at: :asc, created_at: :asc) }
  scope :unread, -> { where(read_at: nil) }
  scope :from_guest, -> { where(sender_role: "guest") }

  def from_guest? = sender_role == "guest"
  def from_staff? = sender_role == "staff"

  private

  def set_sent_at
    self.sent_at ||= Time.current
  end

  # Existing callers create messages with a direction and no role; they keep
  # working and get the role the direction implies.
  def derive_sender_role
    self.sender_role ||= DIRECTION_DEFAULT_SENDER_ROLES[direction]
  end

  # Every writer announces itself from here rather than from its own caller:
  # the guest's line, the bot's answer and a staff reply are one row each, and
  # a new writer added later cannot forget to push.
  #
  # Two streams, because the same row is not the same message on each side --
  # "You" to the guest, "Guest" in the inbox -- so each side gets its own
  # signed stream and its own renderer. Appending rather than refreshing: a
  # refresh would fight the reader's scroll position and wipe half-typed text.
  def broadcast_to_both_sides
    return if conversation.blank?

    broadcast_to_guest
    broadcast_to_staff
    broadcast_to_inbox
  end

  # The list everybody else is looking at. A thread's first message is also its
  # arrival: until it exists there is nothing to show in a row and no telling
  # which tabs it belongs on.
  def broadcast_to_inbox
    conversation.broadcast_arrival_to_inbox if first_in_conversation?
    conversation.broadcast_to_inbox
  end

  def first_in_conversation?
    conversation.messages.limit(2).count == 1
  end

  # The empty-state line has to go before the first bubble lands on top of it.
  # Removing a target that is not there is a no-op, so this is safe every time.
  def broadcast_to_guest
    broadcast_remove_to([ conversation, :guest ], target: "#{PublicUI::Chat::Log::DEFAULT_ID}-empty")
    broadcast_append_to(
      [ conversation, :guest ],
      target: PublicUI::Chat::Log::DEFAULT_ID,
      renderable: PublicUI::Chat::Message.new(message: self, hotel: conversation.hotel)
    )
  end

  def broadcast_to_staff
    broadcast_append_to(
      [ conversation, :staff ],
      target: HotelPortal::Inbox::Log.dom_id_for(conversation),
      renderable: HotelPortal::Inbox::Message.new(message: self)
    )
  end

  # The inbox sorts on the conversation row, so it has to learn about the
  # message. Left to callers this drifts the first time one of them forgets.
  def touch_conversation
    return if conversation.blank?

    attributes = { last_message_at: sent_at }
    attributes[:last_guest_message_at] = sent_at if from_guest?
    conversation.update_columns(**attributes, updated_at: Time.current)
  end
end
