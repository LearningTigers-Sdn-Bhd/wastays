class Feature < ApplicationRecord
  belongs_to :feature_group
  has_many :plan_features, dependent: :destroy
  has_many :plans, through: :plan_features

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :ordered, -> { order(:position) }

  private

  def generate_slug
    self.slug ||= name&.parameterize&.tr("-", "_") if name.present?
  end
end
