class ComplaintRequest < ApplicationRecord
  belongs_to :booking

  validates :complaint_details, presence: true
  validates :requested_at, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def display_requested_at
    requested_at || created_at
  end
end
