class ProspectMessage < ApplicationRecord
  DIRECTIONS = %w[inbound outbound system].freeze

  belongs_to :prospect

  validates :direction, presence: true, inclusion: { in: DIRECTIONS }
  validates :body, presence: true

  before_validation :set_sent_at, on: :create

  scope :chronological, -> { order(sent_at: :asc, created_at: :asc) }

  private

  def set_sent_at
    self.sent_at ||= Time.current
  end
end
