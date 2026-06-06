class JournalBatch < ApplicationRecord
  belongs_to :hotel
  has_many :entries, class_name: "JournalBatchEntry", dependent: :destroy

  validates :business_date, presence: true, uniqueness: { scope: :hotel_id }
  validates :status, presence: true
end
