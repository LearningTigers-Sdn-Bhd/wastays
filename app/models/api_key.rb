class ApiKey < ApplicationRecord
  belongs_to :bearer, polymorphic: true, optional: true

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[active revoked] }

  before_validation :generate_token, on: :create

  scope :active, -> { where(status: "active") }

  def self.authenticate(token)
    key = active.find_by(token: token)
    if key
      key.update_column(:last_used_at, Time.current)
      key
    end
  end

  def superadmin?
    bearer.nil?
  end

  def hotel_restricted?
    bearer_type == "Hotel"
  end

  def account_restricted?
    bearer_type == "Account"
  end

  private

  def generate_token
    self.token ||= "ws_#{SecureRandom.alphanumeric(32)}"
  end
end
