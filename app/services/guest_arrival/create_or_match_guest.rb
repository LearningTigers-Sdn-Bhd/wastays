require "ostruct"

module GuestArrival
  class CreateOrMatchGuest
    def initialize(params)
      @name = params[:name]
      @email = params[:email]&.downcase&.strip
      @phone = params[:phone]&.strip
      @government_id = params[:government_id]&.downcase&.strip
      @gender = params[:gender]&.downcase&.strip
      @country = params[:country]&.downcase&.strip
      @document_type = params[:document_type]&.downcase&.strip
      @date_of_birth = params[:date_of_birth].presence
      @marketing_consent = params[:marketing_consent]
      @privacy_consent = params[:privacy_consent]
      @created_by_hotel_id = params[:created_by_hotel_id]
    end

    def call
      guest = find_existing_guest

      if guest
        updates = {}
        updates[:name] = @name if @name.present? && guest.name != @name
        updates[:country] = @country if @country.present? && guest.country.blank?
        updates[:gender] = @gender if @gender.present? && guest.gender.blank?
        updates[:document_type] = @document_type if @document_type.present? && guest.document_type.blank?
        updates[:government_id] = @government_id if @government_id.present? && guest.government_id.blank?
        updates[:date_of_birth] = @date_of_birth if @date_of_birth.present? && guest.date_of_birth.blank?

        if @marketing_consent.present? || @privacy_consent.present?
          guest.metadata ||= {}
          if @marketing_consent.present?
            guest.metadata["marketing_consent"] = @marketing_consent == "1" || @marketing_consent == true
            guest.metadata["marketing_consent_updated_at"] = Time.current.iso8601
          end
          if @privacy_consent.present?
            guest.metadata["privacy_consent"] = @privacy_consent == "1" || @privacy_consent == true
            guest.metadata["privacy_consent_updated_at"] = Time.current.iso8601
          end
        end

        guest.update(updates) if updates.any? || guest.metadata_changed?
      else
        metadata = {}
        if @marketing_consent.present?
          metadata["marketing_consent"] = @marketing_consent == "1" || @marketing_consent == true
          metadata["marketing_consent_updated_at"] = Time.current.iso8601
        end
        if @privacy_consent.present?
          metadata["privacy_consent"] = @privacy_consent == "1" || @privacy_consent == true
          metadata["privacy_consent_updated_at"] = Time.current.iso8601
        end

        guest = Guest.create!(
          name: @name,
          email: @email,
          phone: @phone,
          government_id: @government_id,
          country: @country,
          gender: @gender,
          document_type: @document_type,
          date_of_birth: @date_of_birth,
          metadata: metadata,
          created_by_hotel_id: @created_by_hotel_id
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

      # 2. Match by email if provided (More unique than phone)
      if @email.present?
        guest = Guest.find_by(email: @email)
        return guest if guest
      end

      # 3. Match by phone if provided
      if @phone.present?
        guest = Guest.find_by(phone: @phone)
        return guest if guest
      end

      nil
    end
  end
end
