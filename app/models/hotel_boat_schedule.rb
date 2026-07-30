# frozen_string_literal: true

# One slot on the property's daily boat timetable, carrying the meals a guest on
# it is entitled to. These flags are the single source of truth for Meal Prep --
# HotelBoatSetting only supplies their defaults when a slot is created.
class HotelBoatSchedule < ApplicationRecord
  KINDS = %w[boat_in boat_out].freeze
  MEALS = HotelBoatSetting::MEALS

  # A slot is a wall-clock label ("the 08:00 boat"), not an instant. Left
  # zone-aware, Rails would parse "08:00" in whatever zone the request runs in
  # and read it back shifted -- an 08:00 slot reads as 22:00 to a viewer in
  # Hawaii. Excluding :time here keeps the label the label.
  self.time_zone_aware_types = [ :datetime ]

  belongs_to :hotel

  scope :active, -> { where(archived_at: nil) }
  scope :boat_in, -> { where(kind: "boat_in") }
  scope :boat_out, -> { where(kind: "boat_out") }
  scope :in_service_order, -> { order(:time, :id) }

  validates :kind, inclusion: { in: KINDS }
  validates :time, presence: true
  validates :time, uniqueness: { scope: %i[hotel_id kind], message: "already has a slot at this time" }

  def archived?
    archived_at.present?
  end

  # Retired rather than destroyed: bookings already made against this slot still
  # resolve their meals through it.
  def archive!
    update!(archived_at: Time.current)
  end

  def restore!
    update!(archived_at: nil)
  end

  def meals
    MEALS.select { |meal| public_send(:"has_#{meal}") }
  end

  def time_of_day
    time&.strftime("%H:%M")
  end
end
