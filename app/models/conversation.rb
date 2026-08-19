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
  MODES = %w[bot human].freeze
  STATUSES = %w[open closed].freeze

  belongs_to :prospect
  belongs_to :assigned_user, class_name: "User", optional: true

  has_many :messages,
           -> { chronological },
           class_name: "ProspectMessage",
           inverse_of: :conversation,
           dependent: :destroy

  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :mode, presence: true, inclusion: { in: MODES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :awaiting_staff, -> { open.where(mode: "human") }
  scope :recent_first, -> { order(last_message_at: :desc, created_at: :desc) }

  def bot? = mode == "bot"
  def human? = mode == "human"
  def open? = status == "open"

  # Handing over is one move, not two: the bot stops answering and the thread
  # gains an owner at the same moment.
  def hand_to_human!(user: nil)
    update!(mode: "human", assigned_user: user)
  end

  def return_to_bot!
    update!(mode: "bot", assigned_user: nil)
  end

  def close!(at: Time.current)
    update!(status: "closed", closed_at: at)
  end

  def unread_count = messages.unread.count
end
