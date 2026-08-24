class Prospect < ApplicationRecord
  STAGES = %w[cold warm hot converted].freeze

  belongs_to :hotel
  belongs_to :guest, optional: true
  has_many :prospect_messages, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :hotel_knowledge_diagnostics, dependent: :nullify
  has_one :prospect_conversation_state, dependent: :destroy

  validates :public_id, presence: true, uniqueness: true
  validates :stage, presence: true, inclusion: { in: STAGES }
  # A visitor chatting on the public concierge page has no number to give
  # yet, so identity falls back to public_id. A real number still cannot be
  # claimed twice within one hotel.
  validates :phone_number, uniqueness: { scope: :hotel_id }, allow_nil: true

  before_validation :ensure_public_id, on: :create
  before_validation :derive_stage
  before_validation :set_last_contact, on: :create

  scope :recent_first, -> { order(last_contact: :desc, created_at: :desc) }

  def self.lookup_by_phone(phone)
    variants = normalized_phone_variants(phone)
    return none if variants.empty?

    where(phone_number: variants)
  end

  def self.normalized_phone_variants(raw)
    PhoneIdentity.variants(raw)
  end

  def self.generate_public_id
    "prsp_#{SecureRandom.urlsafe_base64(18).tr('-_', '').downcase}"
  end

  def touch_last_contact!(at: Time.current)
    update!(last_contact: at)
  end

  private

  def ensure_public_id
    self.public_id ||= self.class.generate_public_id
  end

  def derive_stage
    self.stage = guest_id.present? ? "converted" : stage.presence || "cold"
  end

  def set_last_contact
    self.last_contact ||= Time.current
  end
end
