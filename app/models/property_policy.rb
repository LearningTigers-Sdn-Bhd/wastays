class PropertyPolicy < ApplicationRecord
  belongs_to :hotel

  validates :check_in_time, presence: true
  validates :check_out_time, presence: true
  validates :currency, presence: true
  validates :usd_rate, presence: true
end
