# frozen_string_literal: true

module Admin::AttractionsHelper
  STATUS_BADGE_VARIANTS = {
    "pending" => :warning,
    "approved" => :success,
    "rejected" => :destructive,
    "archived" => :neutral
  }.freeze

  def attraction_status_badge(attraction)
    render PanelsUI::Badge.new(
      label: attraction.status.titleize,
      variant: STATUS_BADGE_VARIANTS.fetch(attraction.status, :neutral),
      size: :sm,
      indicator: true
    )
  end

  def attraction_location(attraction)
    [ attraction.city, attraction.country ].compact_blank.join(", ").presence || "Location text not added"
  end

  def attraction_coordinates(attraction)
    return "Coordinates not available" if attraction.latitude.blank? || attraction.longitude.blank?

    "#{number_with_precision(attraction.latitude, precision: 5)}, #{number_with_precision(attraction.longitude, precision: 5)}"
  end
end
