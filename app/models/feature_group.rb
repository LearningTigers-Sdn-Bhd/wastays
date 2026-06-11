class FeatureGroup < ApplicationRecord
  has_many :features, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug, on: :create

  scope :ordered, -> { order(:position) }

  private

  def generate_slug
    self.slug ||= name&.parameterize if name.present?
  end
end
