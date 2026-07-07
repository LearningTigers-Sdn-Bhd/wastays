class BookingGuest < ApplicationRecord
  belongs_to :booking
  belongs_to :guest

  validates :is_primary, inclusion: { in: [ true, false ] }

  after_commit :sync_booking_vip_status, on: [ :create, :update ]

  private

  def sync_booking_vip_status
    if guest.vip?
      booking.update!(vip: true)
    end
  end
end
