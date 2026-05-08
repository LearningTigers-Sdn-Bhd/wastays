class Role < ApplicationRecord
  belongs_to :account, optional: true
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  has_many :user_hotel_accesses, dependent: :restrict_with_error
  has_many :staff_invitations, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :account_id }

  before_validation :generate_slug, on: :create

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end
end
