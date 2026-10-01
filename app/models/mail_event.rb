# frozen_string_literal: true

class MailEvent < ApplicationRecord
  STATUSES = %w[sent failed].freeze

  validates :mailer, :sent_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(sent_at: :desc, id: :desc) }
end
