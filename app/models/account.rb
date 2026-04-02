class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :hotels, dependent: :destroy
  has_many :roles, dependent: :destroy
  has_many :payment_settings, as: :settable, dependent: :destroy
  has_one :banking_detail, dependent: :destroy

  accepts_nested_attributes_for :banking_detail, update_only: true

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, presence: true

  STATUSES = %w[active suspended pending_review].freeze

  before_validation :generate_slug, on: :create

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end
end
