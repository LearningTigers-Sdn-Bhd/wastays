class PaymentSetting < ApplicationRecord
  belongs_to :settable, polymorphic: true

  encrypts :api_key
  encrypts :secret_key
  encrypts :webhook_secret

  validates :gateway, presence: true
  validates :status, presence: true
  
  STATUSES = %w[active inactive testing].freeze

  scope :active, -> { where(status: 'active') }
end
