# frozen_string_literal: true

class Amenity < ApplicationRecord
  validates :name, :slug, :amenity_type, :category, presence: true
  validates :slug, uniqueness: { scope: :amenity_type }

  enum :amenity_type, { hotel: "hotel", room: "room" }

  scope :ordered, -> { order(:name) }

  def self.categorized(type)
    where(amenity_type: type)
      .ordered
      .group_by(&:category)
      .sort_by { |category, _items| category }
      .map do |category, items|
        {
          category: category,
          items: items.map(&:slug)
        }
      end
  end

  def to_h
    {
      id: slug,
      name: name,
      icon: icon,
      channex_id: channex_id
    }.compact
  end
end
