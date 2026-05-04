class Prospect < ApplicationRecord
  STAGES = %w[cold warm hot converted].freeze

  belongs_to :hotel
  belongs_to :guest, optional: true
  has_many :prospect_profile_facts, dependent: :destroy
  has_many :prospect_messages, dependent: :destroy
  has_one :prospect_conversation_state, dependent: :destroy

  validates :phone_number, presence: true
  validates :stage, presence: true, inclusion: { in: STAGES }
  validates :phone_number, uniqueness: { scope: :hotel_id }

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

  def touch_last_contact!(at: Time.current)
    update!(last_contact: at)
  end

  private

  def derive_stage
    self.stage = guest_id.present? ? "converted" : stage.presence || "cold"
  end

  def set_last_contact
    self.last_contact ||= Time.current
  end
end
