# frozen_string_literal: true

class Attraction < ApplicationRecord
  STATUSES = %w[pending approved rejected archived].freeze

  belongs_to :source_hotel, class_name: "Hotel", optional: true
  belongs_to :submitted_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :merged_into, class_name: "Attraction", optional: true

  has_many :merged_attractions,
    class_name: "Attraction",
    foreign_key: :merged_into_id,
    dependent: :nullify,
    inverse_of: :merged_into
  has_many :hotel_nearby_attractions, dependent: :destroy
  has_many :hotels, through: :hotel_nearby_attractions

  enum :status, STATUSES.index_by(&:itself), prefix: true, validate: true

  before_validation :normalize_registry_identity

  validates :name, presence: true
  validates :coordinate_fingerprint,
    uniqueness: { conditions: -> { where(status: %w[pending approved]) } },
    allow_nil: true,
    if: -> { status_pending? || status_approved? }
  validates :review_note, presence: true, if: :status_rejected?
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  scope :active, -> { where(status: %w[pending approved]) }
  scope :approved_for_suggestions, -> { status_approved.where.not(latitude: nil, longitude: nil) }
  scope :visible_to_hotel, lambda { |hotel|
    where(status: "approved").or(where(status: "pending", source_hotel_id: hotel.id))
  }

  def display_description
    shared_summary.presence || name
  end

  def visible_to_guests_for?(hotel)
    return false unless status_approved? || status_pending?

    hotel_nearby_attractions.exists?(hotel: hotel)
  end

  private

  def normalize_registry_identity
    self.normalized_name = Attractions::Fingerprint.normalize_name(name)
    self.coordinate_fingerprint = if name.present? && latitude.present? && longitude.present?
      Attractions::Fingerprint.call(name: name, latitude: latitude, longitude: longitude)
    end
  end
end
