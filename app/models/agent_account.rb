class AgentAccount < ApplicationRecord
  include HotelScopable

  belongs_to :hotel
  has_many :bookings, dependent: :nullify

  ACCOUNT_TYPES = %w[company travel_agent government airline].freeze

  validates :name, presence: true
  validates :agent_code, presence: true, uniqueness: { scope: :hotel_id }
  validates :account_type, presence: true, inclusion: { in: ACCOUNT_TYPES }

  before_validation :generate_agent_code, on: :create

  private

  def generate_agent_code
    return if agent_code.present?

    loop do
      self.agent_code = SecureRandom.alphanumeric(6).upcase
      break unless AgentAccount.exists?(hotel_id: hotel_id, agent_code: agent_code)
    end
  end
end
