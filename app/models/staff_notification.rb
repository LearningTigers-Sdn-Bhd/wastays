# frozen_string_literal: true

class StaffNotification < ApplicationRecord
  SEVERITIES = %w[info warning critical].freeze

  belongs_to :hotel
  belongs_to :recipient, class_name: "User", inverse_of: :staff_notifications
  belongs_to :subject, polymorphic: true

  validates :notification_type, :title, :message, :deduplication_key, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validates :deduplication_key, uniqueness: true
  validate :subject_belongs_to_hotel

  scope :active, -> { where(resolved_at: nil) }
  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def read? = read_at.present?
  def resolved? = resolved_at.present?

  private

  def subject_belongs_to_hotel
    return unless hotel && subject.respond_to?(:hotel_id)
    return if subject.hotel_id == hotel_id

    errors.add(:subject, "must belong to the same hotel")
  end
end
