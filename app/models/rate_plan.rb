class RatePlan < ApplicationRecord
  belongs_to :room_type
  has_many :room_rates, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy

  validates :name, presence: true
  validates :sell_mode, presence: true, inclusion: { in: %w[per_room per_person] }
  validates :currency, presence: true

  def self.sell_modes
    %w[per_room per_person]
  end
end
