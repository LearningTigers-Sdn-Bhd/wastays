# frozen_string_literal: true

class HotelWifiNetwork < ApplicationRecord
  belongs_to :hotel

  encrypts :password

  enum :security_type, { protected: "protected", open: "open" }, prefix: true
  enum :access_scope, {
    checked_in_guests: "checked_in_guests",
    confirmed_guests: "confirmed_guests",
    staff_only: "staff_only"
  }, prefix: true

  validates :label, :ssid, :security_type, :access_scope, presence: true
  validates :ssid, uniqueness: { scope: :hotel_id, case_sensitive: false }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :password, presence: true, if: :security_type_protected?
  validates :primary_network, uniqueness: { scope: :hotel_id }, if: :primary_network?

  before_validation :clear_open_network_password

  scope :active, -> { where(active: true) }
  scope :in_display_order, -> { order(primary_network: :desc, position: :asc, id: :asc) }
  # The networks an in-house guest may read. A staff_only network never
  # reaches a guest.
  scope :for_guest, -> { active.where(access_scope: %w[checked_in_guests confirmed_guests]) }

  private

  def clear_open_network_password
    self.password = nil if security_type_open?
  end
end
