class ChannelMapping < ApplicationRecord
  belongs_to :mappable, polymorphic: true

  validates :provider, presence: true
  validates :external_id, presence: true
  validates :provider, uniqueness: { scope: [ :mappable_type, :mappable_id ] }
  validates :external_id, uniqueness: { scope: :provider }

  PROVIDERS = %w[channex].freeze
end
