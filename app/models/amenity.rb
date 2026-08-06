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
          items: items.map(&:to_h)
        }
      end
  end

  def self.lookup_map(type)
    @lookup_maps ||= {}
    @lookup_maps[type] ||= where(amenity_type: type).ordered.map(&:to_h).index_by { |a| a[:id] }
  end

  def to_h
    {
      id: slug,
      name: name,
      icon: icon,
      category: category,
      channex_id: channex_id
    }.compact
  end
end
