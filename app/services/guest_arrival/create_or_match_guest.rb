require 'ostruct'

module GuestArrival
  class CreateOrMatchGuest
    def initialize(params)
      @name = params[:name]
      @email = params[:email]&.downcase&.strip
      @phone = params[:phone]&.strip
      @government_id = params[:government_id]&.strip
    end

    def call
      guest = find_existing_guest
      
      if guest
        # Update name if it was missing or update metadata
        guest.update(name: @name) if guest.name.blank?
      else
        guest = Guest.create!(
          name: @name,
          email: @email,
          phone: @phone,
          government_id: @government_id
        )
      end

      OpenStruct.new(success?: true, guest: guest, is_repeat?: guest.bookings.revenue_generating.exists?)
    end

    private

    def find_existing_guest
      # 1. Match by government ID if provided
      if @government_id.present?
        guest = Guest.find_by(government_id: @government_id)
        return guest if guest
      end

      # 2. Match by phone if provided
      if @phone.present?
        guest = Guest.find_by(phone: @phone)
        return guest if guest
      end

      # 3. Match by email if provided
      if @email.present?
        guest = Guest.find_by(email: @email)
        return guest if guest
      end

      nil
    end
  end
end
