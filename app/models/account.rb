class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :hotels, dependent: :destroy
  has_many :roles, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :staff_invitations, -> { staff }, class_name: "StaffInvitation"
  has_many :corporate_invitations, -> { corporate }, class_name: "CorporateInvitation"
  has_many :hotel_corporate_accounts, foreign_key: :corporate_account_id, dependent: :restrict_with_error
  has_many :corporate_hotels, through: :hotel_corporate_accounts, source: :hotel
  has_many :payment_settings, as: :settable, dependent: :destroy
  has_one :banking_detail, dependent: :destroy

  accepts_nested_attributes_for :banking_detail, update_only: true

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, presence: true

  STATUSES = %w[active suspended pending_review].freeze
  ACCOUNT_KINDS = %w[hotel corporate].freeze

  enum :account_kind, ACCOUNT_KINDS.index_by(&:itself), validate: true

  before_validation :generate_slug, on: :create

  validate :corporate_accounts_do_not_own_hotels

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end

  def corporate_accounts_do_not_own_hotels
    return unless corporate? && hotels.exists?

    errors.add(:hotels, "cannot belong to a corporate account")
  end
end
