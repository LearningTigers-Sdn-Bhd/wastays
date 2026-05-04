class ProspectProfileFact < ApplicationRecord
  belongs_to :prospect

  validates :category, presence: true, uniqueness: { scope: :prospect_id }
  validates :value, presence: true
end
