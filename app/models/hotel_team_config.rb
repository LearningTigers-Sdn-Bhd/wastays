# frozen_string_literal: true

class HotelTeamConfig < ApplicationRecord
  belongs_to :hotel

  encrypts :emails

  validates :name, presence: true
  validates :template_type, presence: true
  validates :frequency, numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  before_validation :set_default_frequency, on: :create

  private

  def set_default_frequency
    self.frequency ||= 86400 # 24 hours
  end
end
