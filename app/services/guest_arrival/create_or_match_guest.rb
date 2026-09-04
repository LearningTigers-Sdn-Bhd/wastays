require "ostruct"

module GuestArrival
  class CreateOrMatchGuest
    def initialize(params)
      @name = params[:name]
      @email = params[:email]&.downcase&.strip
      @phone = params[:phone]&.strip
      @government_id = params[:government_id]&.downcase&.strip
      @passport_number = params[:passport_number]&.downcase&.strip
      @gender = params[:gender]&.downcase&.strip
      @city = params[:city]&.strip
      @state_code = params[:state_code].presence
      @postal_code = params[:postal_code]&.strip
      @address_country = params[:address_country]&.strip
      @home_address = params[:home_address]&.strip
      @tin = params[:tin]&.strip
      @country = params[:country]&.downcase&.strip
      @document_type = GuestIdentityDocuments::NormalizeType.call(value: params[:document_type], country: @country) ||
        params[:document_type]&.downcase&.strip
      @date_of_birth = params[:date_of_birth].presence
      @marketing_consent = params[:marketing_consent]
      @privacy_consent = params[:privacy_consent]
      @created_by_hotel_id = params[:created_by_hotel_id]
      @update_profile = params[:update_profile] == true
    end

    def call
      guest = find_existing_guest

      if guest
        updates = {}
        if @update_profile
          updates[:name] = @name if @name.present? && guest.name != @name
          updates[:city] = @city if @city.present? && guest.city != @city
          updates[:state_code] = @state_code if @state_code.present? && guest.state_code != @state_code
          updates[:postal_code] = @postal_code if @postal_code.present? && guest.postal_code != @postal_code
          updates[:address_country] = @address_country if @address_country.present? && guest.address_country != @address_country
          updates[:home_address] = @home_address if @home_address.present? && guest.home_address != @home_address
          updates[:tin] = @tin if @tin.present? && guest.tin != @tin
          updates[:country] = @country if @country.present? && guest.country != @country
          updates[:gender] = @gender if @gender.present? && guest.gender != @gender
          updates[:document_type] = @document_type if @document_type.present? && guest.document_type != @document_type
          updates[:government_id] = @government_id if @government_id.present? && guest.safely_read_encrypted(:government_id) != @government_id
          updates[:passport_number] = @passport_number if @passport_number.present? && guest.safely_read_encrypted(:passport_number) != @passport_number
          updates[:date_of_birth] = @date_of_birth if @date_of_birth.present? && guest.date_of_birth != @date_of_birth
        end

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

        if updates.any? || guest.metadata_changed?
          begin
            guest.update(updates)
          rescue ActiveRecord::Encryption::Errors::Decryption
            # `update` runs dirty-checking, which decrypts the *current* stored
            # value to compare it against the new one. If that stored value was
            # encrypted under a since-rotated/mismatched key, the comparison
            # itself raises. update_columns writes the new value directly
            # (still encrypting it under the current key) without needing to
            # read the old ciphertext, healing the row going forward.
            Rails.logger.warn("[Guest##{guest.id}] update fell back to update_columns after a decrypt failure on the stored value")
            guest.update_columns(updates.merge(metadata: guest.metadata, updated_at: Time.current))
          end
        end
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
          passport_number: @passport_number,
          city: @city,
          state_code: @state_code,
          postal_code: @postal_code,
          address_country: @address_country,
          home_address: @home_address,
          tin: @tin,
          country: @country,
          gender: @gender,
          document_type: @document_type,
          date_of_birth: @date_of_birth,
          metadata: metadata,
          created_by_hotel_id: @created_by_hotel_id
        )
      end

      OpenStruct.new(
        success?: true,
        guest: guest,
        is_repeat?: guest.bookings.revenue_generating.exists?
      )
    end

    private

    def find_existing_guest
      # 1. Match by government ID if provided
      if @government_id.present?
        guest = guest_for_document_number(@government_id)
        return guest if guest
      end

      if @passport_number.present?
        guest = guest_for_document_number(@passport_number)
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

    def guest_for_document_number(number)
      Guest.find_by(government_id: number) || Guest.find_by(passport_number: number)
    end
  end
end
