class Plan < ApplicationRecord
  has_many :plan_features, dependent: :destroy
  has_many :features, through: :plan_features
  has_many :hotels, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position) }

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end
end
